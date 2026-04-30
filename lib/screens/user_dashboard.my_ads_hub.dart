part of 'user_dashboard.dart';

/// واجهة تبويبات «صفحتي» (مسوّق/معلن): راجع `docs/MARKETING_FULL_FLOW_USER_SPEC_AR.md` لربط المراحل.

extension _UserDashboardStateMyAdsHub on _UserDashboardState {
  /// تنبيه بصري على الجرس: طلبات تحتاج مراجعة عروض (لم يُفتح صفحة العروض بعد).
  int get _ownerOffersAttentionCount {
    if (_isGuest || _isMarketerRole) return 0;
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
        physics: const AlwaysScrollableScrollPhysics(),
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

    final bool isMarketer = _isMarketerRole;

    if (isMarketer) {
      final ctrl = _marketerTabsCtrl;
      if (ctrl == null) {
        return _buildHubPreparingState(
          title: AppLocalizations.of(context)!.preparingMarketingTabsTitle,
          onRetry: _ensureSubTabControllers,
        );
      }
      return _buildMarketerMyAds(cs, ctrl);
    }

    final ctrl = _ownerTabsCtrl;
    if (ctrl == null) {
      return _buildHubPreparingState(
        title: AppLocalizations.of(context)!.preparingListingsTabsTitle,
        onRetry: _ensureSubTabControllers,
      );
    }

    return _buildOwnerMyAds(cs, myItems, ctrl);
  }

  Widget _buildHubPreparingState({
    required String title,
    required VoidCallback onRetry,
  }) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return ListView(
      controller: _scrollControllerForOnboardingTab(1),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      children: [
        const SizedBox(height: 70),
        Center(
          child: Column(
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: AppLogoLoading(compact: true, size: 38),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.ifContinuesTapRetry,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retryLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandPrimary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Property> _filterOwnerHubTab(List<Property> items, int tabIndex) {
    return items.where((p) {
      if (p.deletedByUser) return false;
      if (p.deleteApproved) return false;
      if (tabIndex == 7) {
        final st = p.normalizedStatus;
        final soldLike = st == 'sold' || st == 'completed';
        if (!soldLike) return false;
        if (_hiddenCompletedDealPropertyIds.contains(p.id)) return false;
        return true;
      }
      final decision = ListingPostPublishUiHelper.decideFromProperty(p);
      if (!decision.showInOwnerPage) return false;
      return ListingStageUiHelper.ownerTabMatches(
        tabIndex,
        p.effectiveWorkflowStage,
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
    if (tabIndex >= 5) return const <Map<String, dynamic>>[];
    return _ownerListingRequests.where((r) {
      if (!_matchesHubRowSearch(r)) return false;
      if (!_matchesHubRowRanges(r)) return false;
      final decision = ListingPostPublishUiHelper.decideFromRequestRow(
          Map<String, dynamic>.from(r));
      if (decision.kind == ListingUiEntityKind.publishedProperty) return false;
      return ListingStageUiHelper.ownerTabMatches(tabIndex, decision.stage);
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
    final t1 = ar ? 'بانتظار التعاقد' : 'Awaiting contracting';
    final t2 = ar ? 'لم يتخذ إجراء 72 ساعة' : 'No action (72h)';
    final t3 = ar ? 'مفسوخ / ملغى' : 'Cancelled / terminated';
    final t4 = ar ? 'العقارات المحجوزة' : 'Reserved properties';
    final t5 = ar ? 'إعلاناتي المنشورة' : 'My published ads';
    final t6 = ar ? 'صفقات مكتملة' : 'Completed deals';

    /// فهارس منطقية قديمة لـ [ListingStageUiHelper.ownerTabMatches]: 0,1,3,4 (بدون تبويب «منشور» المكرر).
    const ownerHubLogicalTabs = <int>[0, 1, 3, 4];

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
              t1,
              _ownerMyPageTabBadgeCount(1, myItems),
            ),
            _ownerTabWithBadge(
              t2,
              _ownerMyPageTabBadgeCount(2, myItems),
            ),
            _ownerTabWithBadge(
              t3,
              _ownerMyPageTabBadgeCount(3, myItems),
            ),
            _ownerTabWithBadge(
              t4,
              _ownerMyPageTabBadgeCount(4, myItems),
            ),
            _ownerTabWithBadge(
              t5,
              _ownerMyPageTabBadgeCount(5, myItems),
            ),
            _ownerTabWithBadge(
              t6,
              _ownerMyPageTabBadgeCount(6, myItems),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: ctrl,
            children: [
              ...List.generate(4, (i) {
                final logical = ownerHubLogicalTabs[i];
                final propertyItems = _filterOwnerHubTab(myItems, logical);
                final requestRows = _ownerRequestRowsForTab(logical);
                final emptyText = switch (logical) {
                  0 => l10n.myAdsEmptyWaitingMediator,
                  1 => l10n.myAdsEmptyAwaitContract,
                  3 =>
                    ar ? 'لا توجد عقارات متوقفة هنا' : 'Nothing in this bucket',
                  4 =>
                    ar ? 'لا توجد عقارات مفسوخة هنا' : 'Nothing cancelled here',
                  _ => l10n.myAdsEmptyWaitingMediator,
                };
                return _buildOwnerHubTab(
                  propertyItems: propertyItems,
                  requestRows: requestRows,
                  emptyText: emptyText,
                );
              }),
              _buildOwnerReservationsTab(l10n),
              _buildOwnerPublishedPropertiesList(
                items: _filterOwnerHubTab(myItems, 6),
                emptyText: ar
                    ? 'لا توجد إعلانات منشورة في حسابك'
                    : 'You have no published listings',
              ),
              _buildOwnerCompletedDealsTab(myItems),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOwnerCompletedDealsTab(List<Property> myItems) {
    final items = _filterOwnerHubTab(myItems, 7);
    final hiddenN = _hiddenCompletedDealPropertyIds.length;
    final cs = Theme.of(context).colorScheme;
    final ar = widget.isAr;

    if (_loadingMine && items.isEmpty) {
      return const CartRowSkeletonList(count: 4, topPadding: 16);
    }

    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
      if (p.images.isEmpty) return '';
      return p.images.first.trim();
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 88,
                      height: 72,
                      child: url.isEmpty
                          ? ColoredBox(
                              color: cs.surfaceContainerHigh,
                              child: Icon(
                                Icons.home_work_outlined,
                                color: cs.onSurfaceVariant,
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => ColoredBox(
                                color: cs.surfaceContainerHigh,
                                child: const Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: AppLogoLoading(
                                      compact: true,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) => ColoredBox(
                                color: cs.surfaceContainerHigh,
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                    ),
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
        physics: const AlwaysScrollableScrollPhysics(),
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
      physics: const AlwaysScrollableScrollPhysics(),
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
  }) {
    final hasReq = requestRows.isNotEmpty;
    final hasProp = propertyItems.isNotEmpty;

    if (!hasReq && !hasProp) {
      return _buildOwnerPublishedPropertiesList(
        items: propertyItems,
        emptyText: emptyText,
      );
    }

    // طلب تسويق يعرض صور/بيانات من صف الطلب + المعاينة؛ هذا ليس «إعلان عقار» في القائمة السفلية.
    // إن وُجد طلب ولم يُطابق أي Property نفس التبويب، لا نعرض رسالة «لا يوجد عقار» تحت البطاقة.
    if (hasReq && !hasProp) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          Expanded(
            child: _buildOwnerMarketingRequestsFeed(requestRows),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasReq) ...[
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
          Expanded(
            flex: hasProp ? 2 : 3,
            child: _buildOwnerMarketingRequestsFeed(requestRows),
          ),
          const Divider(height: 20),
          if (hasProp)
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
        ],
        Expanded(
          flex: hasReq && hasProp ? 3 : 1,
          child: _buildOwnerPublishedPropertiesList(
            items: propertyItems,
            emptyText: emptyText,
          ),
        ),
      ],
    );
  }

  /// عرض الصور في بطاقة طلب التسويق: نفس منطق دمج المسوّقين (معاينة ثم payload).
  List<String> _effectiveImageUrlsForOwnerRequestRow(
    Map<String, dynamic> row,
  ) {
    final payload = _mergedJsonPayloadForRow(row);
    final fromPayloadUrls = _payloadImagePaths(payload)
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
    final direct = mergedDyn
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
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

  Property? _linkedPropertyForOwnerRequestCard(Map<String, dynamic> row) {
    final pid = (row['preview_property_id'] ?? '').toString().trim();
    if (pid.isEmpty) return null;
    final cached = _propertyCache[pid] ?? _myPropertyById[pid];
    if (cached != null) return cached;
    try {
      return _mine.firstWhere((p) => p.id == pid);
    } catch (_) {}
    try {
      return _all.firstWhere((p) => p.id == pid);
    } catch (_) {}
    return null;
  }

  Widget _buildOwnerLinkedPropertyCard(
    Map<String, dynamic> row,
    Property property,
    ListingWorkflowUiContext wfCtx,
  ) {
    final l10n = AppLocalizations.of(context);
    final id = (row['request_id'] ?? row['id'] ?? '').toString().trim();
    final uid = _uid.isEmpty ? 'guest' : _uid;
    final isOwner = uid != 'guest' && property.ownerId == uid;
    final contractId = (row['contract_id'] ?? '').toString().trim();
    final inContractingTab =
        ListingStageUiHelper.ownerTabMatches(1, wfCtx.stage);

    void open() {
      if (id.isEmpty) {
        _openDetails(property);
        return;
      }
      unawaited(_openOwnerListingRequestFromRow(row, requestStatusId: id));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _RealEstateCard(
          property: property,
          isOwner: isOwner,
          isAr: widget.isAr,
          bankColor: _brandPrimary,
          favorite: !_isGuest && _isFav(property.id),
          onToggleFav: _isGuest
              ? () => _showLoginDialog()
              : () => _toggleFav(property.id),
          onOpenDetails: open,
          activeCartHoldsCount: _activeReservationHoldCount(property.id),
          isReserved: _isReservedByAnyone(property.id),
          reservedUntil: _reservedUntil(property.id),
          reservedByName: _reservedByName(property.id),
          onAddToCart: null,
          currentUserId: uid,
          showEditDelete: false,
          onEditProperty: null,
          onDeleteProperty: null,
          timeAgo: _timeAgo,
          forceListLayout: true,
          relaxTextTruncation: false,
          canShowCartButton: false,
          onViewsPillTap: (ctx) {
            final pubId = (property.publishedByMarketerId ?? '').trim();
            final isPm = uid.isNotEmpty && pubId == uid;
            PropertyViewService.showSheet(
              context: ctx,
              sb: _sb,
              propertyId: property.id,
              viewsCount: property.views,
              isOwner: isOwner,
              isPublishingMarketer: isPm,
              isAr: widget.isAr,
            );
          },
          showListingQuickActions: false,
          onCopyListingWebLink: _copyListingPublicLink,
          onShareListingFromCard: () => _shareListingFromCard(property),
          showFullOwnerLegalNameOnCard: false,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: _buildSmartMarketerActionBar([
            if (inContractingTab || wfCtx.showOwnerOffersEntry)
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
            if (inContractingTab && contractId.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => unawaited(_openOwnerContractChat(contractId)),
                icon: const Icon(Icons.chat_bubble_outline, size: 22),
                label: Text(
                  widget.isAr
                      ? 'محادثة العقد والموافقة'
                      : 'Contract chat & approval',
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
          ]),
        ),
      ],
    );
  }

  Widget _buildOwnerListingRequestCard(
    Map<String, dynamic> row, {
    required bool horizontalLayout,
  }) {
    final l10n = AppLocalizations.of(context);
    final id = (row['request_id'] ?? row['id'] ?? '').toString().trim();
    final purposeTitle =
        PropertyListingDisplay.purposeLabelForRequestRow(row, widget.isAr);
    final subtitle =
        (row['request_title'] ?? row['title'] ?? '').toString().trim();
    final city = PropertyListingDisplay.cityLineFromRequestRow(row);
    final wfCtx = ListingWorkflowUiContext.fromListingRequest(
        Map<String, dynamic>.from(row));
    final linkedProperty = _linkedPropertyForOwnerRequestCard(row);
    if (linkedProperty != null) {
      return _buildOwnerLinkedPropertyCard(row, linkedProperty, wfCtx);
    }

    final cs = Theme.of(context).colorScheme;
    final statusLine = widget.isAr ? wfCtx.statusLabelAr : wfCtx.statusLabelEn;
    final pda = row['permit_deadline_at'];
    final deadline = pda != null ? DateTime.tryParse(pda.toString()) : null;

    final accent = PropertyListingDisplay.accentForRequestRow(row);
    final areaIc = PropertyListingDisplay.areaIconForRequestRow(row);
    final urls = _effectiveImageUrlsForOwnerRequestRow(row);
    final mergedReq = _mergedJsonPayloadForRow(row);
    final vidRaw =
        (mergedReq['request_video_path'] ?? mergedReq['video_url'] ?? '')
            .toString()
            .trim();
    var coverVid = false;
    final lgReq = mergedReq['listing_guidance'];
    if (lgReq is Map) {
      final c = (lgReq['cover_primary'] ?? 'image').toString().toLowerCase();
      coverVid = c == 'video';
    }

    Map<String, dynamic>? snapMap;
    final rawSnap = row['preview_marketing_license_snapshot'] ??
        row['marketing_license_snapshot'];
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

    final reqCreated = parseDt(row['created_at']);
    final propPublished = parseDt(row['preview_published_at']);

    // بطاقة صفحتي مختصرة؛ بيانات المالك/المسوق التفصيلية تظهر داخل التفاصيل.
    final ownerHint = '';

    final usageTuples = <(IconData, String)>[];

    final priceRaw = row['preview_price'];
    final price = priceRaw is num
        ? priceRaw.toDouble()
        : double.tryParse('$priceRaw') ?? 0;
    final areaRaw = row['preview_area'];
    final area =
        areaRaw is num ? areaRaw.toDouble() : double.tryParse('$areaRaw') ?? 0;
    final cur = (row['preview_currency'] ?? 'SAR').toString().trim();
    final curCode = cur.isEmpty ? 'SAR' : cur;

    final cityNorm = city.trim();
    final subtitleNorm = subtitle.trim();
    final cityRedundantInSubtitle = cityNorm.isEmpty ||
        cityNorm == '-' ||
        (subtitleNorm.isNotEmpty &&
            subtitleNorm.toLowerCase().contains(cityNorm.toLowerCase()));

    void open() {
      if (id.isEmpty) return;
      unawaited(_openOwnerListingRequestFromRow(row, requestStatusId: id));
    }

    final contractId = (row['contract_id'] ?? '').toString().trim();
    final inContractingTab =
        ListingStageUiHelper.ownerTabMatches(1, wfCtx.stage);
    final inWaitingOffersTab =
        ListingStageUiHelper.ownerTabMatches(0, wfCtx.stage);
    final showOwnerActionStrip = !_isGuest &&
        !_isMarketerRole &&
        (inContractingTab || inWaitingOffersTab);

    final imageH = horizontalLayout ? 168.0 : 112.0;
    final imageW = horizontalLayout ? 132.0 : double.infinity;

    final imageBlock = SizedBox(
      width: imageW,
      height: imageH,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _PropertyImage(
            urls: urls,
            fit: BoxFit.cover,
            videoPathOrUrl: (vidRaw.isNotEmpty && (urls.isEmpty || coverVid))
                ? vidRaw
                : null,
            isAr: widget.isAr,
            allowInlineVideo: !kIsWeb,
          ),
          if (urls.isNotEmpty || vidRaw.isNotEmpty)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          if (!_isGuest && !_isMarketerRole)
            PositionedDirectional(
              top: 6,
              end: 6,
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  tooltip: widget.isAr ? 'تتبع نشاط الطلب' : 'Request activity',
                  onPressed: () => _showOwnerRequestActivityDialog(row),
                  icon: const Icon(
                    Icons.visibility_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ),
            ),
          PositionedDirectional(
            bottom: 6,
            end: 6,
            child: Icon(Icons.chevron_right, color: Colors.white70),
          ),
        ],
      ),
    );

    final textBlock = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isMarketerRole &&
              marketerTop != null &&
              marketerTop.trim().isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.business_outlined, size: 16, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.isAr
                        ? 'جهة التسويق العقاري: $marketerTop'
                        : 'Marketing entity: $marketerTop',
                    maxLines: 2,
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
            const SizedBox(height: 8),
          ],
          if (ownerHint.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.person_outline,
                  size: 15,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.isAr ? 'المالك: $ownerHint' : 'Owner: $ownerHint',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Text(
            purposeTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: accent,
            ),
          ),
          if (usageTuples.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final u in usageTuples)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent.withOpacity(0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(u.$1, size: 14, color: accent),
                        const SizedBox(width: 4),
                        Text(
                          '${u.$2} ✓',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (subtitle.isNotEmpty &&
              subtitle.trim() != purposeTitle.trim()) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: horizontalLayout ? 2 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (!cityRedundantInSubtitle) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 15,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    city,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(areaIc, size: 15, color: _brandPrimary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        widget.isAr
                            ? '${AppMoney.formatNumber(area, isAr: widget.isAr, maxFractionDigits: 0)} م²'
                            : '${AppMoney.formatNumber(area, isAr: widget.isAr, maxFractionDigits: 0)} m²',
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
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AppMoneyLine(
                    amount: AppMoney.roundSar(price, fractionDigits: 0),
                    currencyCode: curCode,
                    isAr: widget.isAr,
                    maxFractionDigits: 0,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if ((wfCtx.isPublishedPublic && propPublished != null) ||
              (!wfCtx.isPublishedPublic && reqCreated != null)) ...[
            const SizedBox(height: 8),
            if (wfCtx.isPublishedPublic && propPublished != null)
              Text(
                widget.isAr
                    ? 'نشر الطلب: ${_timeAgo(propPublished, widget.isAr)}'
                    : 'Request published: ${_timeAgo(propPublished, widget.isAr)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              )
            else if (!wfCtx.isPublishedPublic && reqCreated != null)
              Text(
                widget.isAr
                    ? 'إنشاء الطلب: ${_timeAgo(reqCreated, widget.isAr)}'
                    : 'Request created: ${_timeAgo(reqCreated, widget.isAr)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
          const SizedBox(height: 6),
          Text(
            statusLine,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cs.primary,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          ListingWorkflowProgressStrip(
            stage: wfCtx.stage,
            compact: true,
            dense: true,
            deadline: deadline ?? wfCtx.primaryDeadline,
          ),
          Builder(
            builder: (ctx) {
              final previewPid =
                  (row['preview_property_id'] ?? '').toString().trim();
              final codeSrc = previewPid.isNotEmpty ? previewPid : id;
              final code = DisplayIds.tenDigit(codeSrc);
              if (code.isEmpty) return const SizedBox.shrink();
              final scheme = Theme.of(ctx).colorScheme;
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
                          color: scheme.primary,
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
                      icon: Icon(Icons.copy_rounded, color: scheme.primary),
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
        ],
      ),
    );

    final cardInner = horizontalLayout
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                imageBlock,
                Expanded(child: textBlock),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              imageBlock,
              textBlock,
            ],
          );

    return Card(
      elevation: 1,
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accent.withOpacity(0.35), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: open,
            child: cardInner,
          ),
          if (showOwnerActionStrip)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _buildSmartMarketerActionBar([
                OutlinedButton.icon(
                  onPressed: open,
                  icon: const Icon(Icons.open_in_new, size: 22),
                  label: Text(
                    widget.isAr ? 'عرض التفاصيل' : 'View details',
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
                if (inContractingTab || wfCtx.showOwnerOffersEntry)
                  FilledButton.icon(
                    onPressed: id.isEmpty
                        ? null
                        : () => unawaited(_openOwnerOffersForRequest(id)),
                    icon: const Icon(Icons.rate_review_outlined, size: 22),
                    label: Text(
                      l10n?.ownerBtnRealEstateOffers ??
                          (widget.isAr
                              ? 'العروض العقارية'
                              : 'Real estate offers'),
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
                if (inContractingTab && contractId.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () =>
                        unawaited(_openOwnerContractChat(contractId)),
                    icon: const Icon(Icons.chat_bubble_outline, size: 22),
                    label: Text(
                      widget.isAr
                          ? 'محادثة العقد والموافقة'
                          : 'Contract chat & approval',
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
              ]),
            ),
        ],
      ),
    );
  }

  Future<void> _openOwnerOffersForRequest(String requestId) async {
    if (requestId.isEmpty) return;
    await _pushBody<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => OwnerOffersPage(
          requestId: requestId,
          lang: widget.lang,
        ),
      ),
    );
    if (mounted) await _loadOwnerRequestsBuckets(force: true);
  }

  Future<void> _openOwnerContractChat(String contractId) async {
    if (contractId.isEmpty) return;
    await _pushBody<void>(
      MaterialPageRoute<void>(
        builder: (_) => ListingContractChatPage(
          contractId: contractId,
          lang: widget.lang,
        ),
      ),
    );
    if (mounted) await _loadOwnerRequestsBuckets(force: true);
  }

  ListingWorkflowStage _workflowStageFromMarketerRow(Map<String, dynamic> row) {
    return ListingWorkflowUnified.fromMarketerMergedRow(row);
  }

  String _marketingRequestIdFromRow(Map<String, dynamic> row) {
    return (row['request_id'] ?? row['listing_request_id'] ?? '')
        .toString()
        .trim();
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

    final inviteBlockedByStatus = inviteGate == 'declined' ||
        inviteGate == 'expired' ||
        inviteGate == 'offered' ||
        inviteGate == 'accepted' ||
        inviteGate == 'withdrawn';

    // للدعوات: لا نستخدم listing_request_status (غالباً active/published) كحظر — ذلك كان يُعطّل زر العرض.
    final workflowClosedForOffers = type == 'invite'
        ? closedAfterMarketing.contains(workflowRaw)
        : (workflowRaw == 'published' ||
            requestStatusRaw == 'published' ||
            requestStatusRaw == 'live' ||
            requestStatusRaw == 'active');

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
              ? 'لا يمكن تقديم عرض لهذه الدعوة في حالتها الحالية.'
              : 'You cannot submit an offer for this invite in its current state.';
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

  List<Map<String, dynamic>> _filterMarketerRowsForTab(int tabIndex) {
    bool involved(Map<String, dynamic> r) {
      return (r['marketer_id'] ?? '').toString() == _uid ||
          (r['selected_marketer_id'] ?? '').toString() == _uid;
    }

    Iterable<Map<String, dynamic>> sourceRows() sync* {
      switch (tabIndex) {
        case 0:
          yield* _mkInvites;
          return;
        case 1:
          yield* _mkOffers;
          yield* _mkContracts;
          return;
        case 2:
          yield* _mkPermits;
          return;
        case 3:
          yield* _mkPublished;
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
      if (tabIndex == 1 &&
          (r['_hubKind'] ?? r['_ui_type'] ?? '').toString() == 'offer' &&
          _marketerRowHasContract(r)) {
        return false;
      }
      // تبويب «السوق العقاري» (0): المصدر _mkInvites فقط — التصفية حسب مرحلة الطلب
      // كانت تُخفي كل الدعوات عندما يكون status الطلب active/published أو workflow غير waiting_marketers.
      if (tabIndex == 0) return true;
      final st = _workflowStageFromMarketerRow(r);
      return ListingStageUiHelper.marketerTabMatches(
        tabIndex,
        st,
        publishedByMe: tabIndex == 3,
        involvedInContract: involved(r),
        hasInviteOrOffer: true,
      );
    }).toList();
  }

  Widget _marketerTabWithBadge(String label, int count) {
    if (count <= 0) return Tab(text: label);
    final cs = Theme.of(context).colorScheme;
    return Tab(
      child: Badge(
        backgroundColor: cs.error,
        label: Text(
          count > 99 ? '99+' : '$count',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: cs.onError,
          ),
        ),
        child: Text(label),
      ),
    );
  }

  /// شارات تبويبات «صفحتي» للمالك — نفس فكرة شارات المسوّق (عدد العناصر الفعلي).
  int _ownerMyPageTabBadgeCount(int tabBarIndex, List<Property> myItems) {
    const logicalFor = <int>[0, 1, 3, 4];
    if (tabBarIndex >= 0 && tabBarIndex < logicalFor.length) {
      final lg = logicalFor[tabBarIndex];
      return _filterOwnerHubTab(myItems, lg).length +
          _ownerRequestRowsForTab(lg).length;
    }
    if (tabBarIndex == 4) return _offers.length;
    if (tabBarIndex == 5) return _filterOwnerHubTab(myItems, 6).length;
    if (tabBarIndex == 6) return _filterOwnerHubTab(myItems, 7).length;
    return 0;
  }

  Widget _ownerTabWithBadge(String label, int count) {
    if (count <= 0) return Tab(text: label);
    final cs = Theme.of(context).colorScheme;
    return Tab(
      child: Badge(
        backgroundColor: cs.error,
        label: Text(
          count > 99 ? '99+' : '$count',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: cs.onError,
          ),
        ),
        child: Text(label),
      ),
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
              _filterMarketerRowsForTab(0).length,
            ),
            _marketerTabWithBadge(
              l10n.marketerTabAwaitingOwner,
              _filterMarketerRowsForTab(1).length,
            ),
            _marketerTabWithBadge(
              ar ? 'التصريح 72 ساعة' : 'Permit 72h',
              _filterMarketerRowsForTab(2).length,
            ),
            _marketerTabWithBadge(
              ar ? 'منشور / محجوز' : 'Published / reserved',
              _filterMarketerRowsForTab(3).length,
            ),
            _marketerTabWithBadge(
              ar ? 'بدون إجراء 72' : 'Inactive 72h',
              _filterMarketerRowsForTab(4).length,
            ),
            _marketerTabWithBadge(
              ar ? 'مفسوخ / ملغى' : 'Terminated',
              _filterMarketerRowsForTab(5).length,
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: ctrl,
            children: [
              _buildMarketerTabBody(
                rows: _filterMarketerRowsForTab(0),
                emptyText: l10n.marketerEmptyInvites,
                type: 'invite',
                marketerInvitesTabLayout: true,
              ),
              _buildMarketerContractingTab(l10n),
              _buildMarketerTabBody(
                rows: _filterMarketerRowsForTab(2),
                emptyText: l10n.marketerEmptyPermits,
                type: 'permit',
              ),
              _buildMarketerTabBody(
                rows: _filterMarketerRowsForTab(3),
                emptyText: l10n.marketerEmptyPublished,
                type: 'published',
              ),
              _buildMarketerTabBody(
                rows: _filterMarketerRowsForTab(4),
                emptyText: ar ? 'لا توجد عقارات متوقفة' : 'Nothing here',
                type: 'invite',
              ),
              _buildMarketerTabBody(
                rows: _filterMarketerRowsForTab(5),
                emptyText: ar ? 'لا توجد عقارات مفسوخة' : 'Nothing cancelled',
                type: 'contract',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMarketerContractingTab(AppLocalizations l10n) {
    final ar = widget.isAr;
    final merged = <Map<String, dynamic>>[
      ..._mkOffers.map((e) => {...e, '_hubKind': 'offer'}),
      ..._mkContracts.map((e) => {...e, '_hubKind': 'contract'}),
    ];
    final filtered = merged.where((r) {
      bool involved(Map<String, dynamic> row) {
        return (row['marketer_id'] ?? '').toString() == _uid ||
            (row['selected_marketer_id'] ?? '').toString() == _uid;
      }

      if (!involved(r)) return false;
      if (!_matchesHubRowSearch(r)) return false;
      if (!_matchesHubRowRanges(r)) return false;

      final st = _workflowStageFromMarketerRow(r);
      final hubKind = (r['_hubKind'] ?? '').toString();

      if (ListingStageUiHelper.marketerTabMatches(
        1,
        st,
        publishedByMe: false,
        involvedInContract: true,
        hasInviteOrOffer: true,
      )) {
        return true;
      }

      // عرض مقدَّم وما زال الطلب في انتظار المسوّقين / اختيار المالك
      if (hubKind == 'offer' && st == ListingWorkflowStage.waitingMarketers) {
        final os = (r['status'] ?? '').toString().toLowerCase();
        if (os == 'owner_rejected' || os == 'rejected' || os == 'withdrawn') {
          return false;
        }
        return true;
      }

      return false;
    }).toList();
    final rows = filtered;

    if (_loadingMarketing && rows.isEmpty) {
      return _buildTabLoadingState(
        title: ar ? 'جارٍ تحميل التعاقد' : 'Loading contracting…',
      );
    }
    if (_errorMarketing != null && rows.isEmpty) {
      return _simpleErrorBox(
        title: ar ? 'تعذر تحميل التعاقد' : 'Failed to load',
        err: _errorMarketing!,
        onRetry: () => _loadMarketerBuckets(force: true),
      );
    }
    if (rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Text(
              l10n.marketerEmptyContracts,
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
    );
  }

  Widget _buildStableTabBar({
    required ColorScheme cs,
    required TabController controller,
    required List<Widget> tabs,
    bool showMarketerScenarioGuide = false,
    bool showOwnerScenarioGuide = false,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.28),
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 8),
            color: cs.shadow.withOpacity(0.05),
          ),
        ],
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TabBar(
          controller: controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          splashBorderRadius: BorderRadius.circular(999),
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => _brandPrimary.withOpacity(0.06),
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          indicatorPadding: EdgeInsets.zero,
          indicator: BoxDecoration(
            color: _brandPrimary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _brandPrimary.withOpacity(0.18),
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
                    vertical: 5,
                  ),
                  child: t,
                ),
              )
              .toList(),
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
    );
  }

  Widget _buildTabLoadingState({
    required String title,
  }) {
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

  String _trMarketingStatus(String? status) {
    final s = (status ?? '').trim().toLowerCase();

    if (widget.isAr) {
      switch (s) {
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
        case 'marketer_selected':
          return 'تم اختيار مسوق';
        case 'contract_pending':
          return 'بانتظار العقد';
        case 'contract_sent':
          return 'أُرسل العقد للمالك';
        case 'contract_returned':
          return 'أُعيد العقد للتعديل';
        case 'contract_signed':
          return 'تم توقيع العقد';
        case 'permit_pending':
          return 'بانتظار التصريح';
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
          return 'مقبول من المالك';
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
        case 'marketer_selected':
          return 'Marketer selected';
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
          return 'Owner accepted';
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

      default:
        return cs.primary;
    }
  }

  String _mkRowTitle(Map<String, dynamic> r) {
    final requestTitle = (r['request_title'] ?? '').toString().trim();
    final previewTitle = (r['preview_title'] ?? '').toString().trim();
    final title = (r['title'] ?? '').toString().trim();
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

  String _mkRowSubLine(Map<String, dynamic> r) {
    final city = (r['request_city'] ?? r['preview_city'] ?? r['city'] ?? '')
        .toString()
        .trim();
    final status = _trMarketingStatus(r['status']?.toString());
    final hub = (r['_hubKind'] ?? r['_ui_type'] ?? '').toString();
    final mkName = (r['_marketer_display_name'] ?? '').toString().trim();
    final mkPhone = (r['_marketer_phone'] ?? '').toString().trim();
    final mkAcct = (r['_marketer_account_type'] ?? '').toString().trim();

    String? marketerLine() {
      if (hub != 'invite' &&
          hub != 'offer' &&
          hub != 'contract' &&
          hub != 'permit') {
        return null;
      }
      final parts = <String>[];
      if (mkName.isNotEmpty) parts.add(mkName);
      if (mkPhone.isNotEmpty) parts.add(mkPhone);
      if (mkAcct.isNotEmpty) {
        parts.add(
          widget.isAr ? 'نوع: $mkAcct' : 'Type: $mkAcct',
        );
      }
      if (parts.isNotEmpty) return parts.join(' · ');
      // دعوة/عرض من جهة المسوّق: غالباً لا يوجد _marketer_* (أنت المسوّق) — اعرض المالك.
      final ownerNm = (r['request_owner_name'] ?? r['preview_owner_name'] ?? '')
          .toString()
          .trim();
      final ownerPh =
          (r['request_owner_phone'] ?? r['preview_owner_phone'] ?? '')
              .toString()
              .trim();
      if (ownerNm.isNotEmpty || ownerPh.isNotEmpty) {
        final ob = <String>[];
        if (ownerNm.isNotEmpty) {
          ob.add(
            widget.isAr ? 'المعلن: $ownerNm' : 'Advertiser: $ownerNm',
          );
        }
        if (ownerPh.isNotEmpty) ob.add(ownerPh);
        return ob.join(' · ');
      }
      return null;
    }

    final ml = marketerLine();

    if (widget.isAr) {
      final base =
          city.isNotEmpty ? '$city • الحالة: $status' : 'الحالة: $status';
      if (ml == null) return base;
      return '$ml\n$base';
    } else {
      final base =
          city.isNotEmpty ? '$city • Status: $status' : 'Status: $status';
      if (ml == null) return base;
      return '$ml\n$base';
    }
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
      'region',
      'area_name',
    ]) {
      final s = (m[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String _marketingLocationText(Map<String, dynamic> r) {
    final city = (r['preview_city'] ?? r['request_city'] ?? r['city'] ?? '')
        .toString()
        .trim();

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

    if (city.isNotEmpty && locMerged.isNotEmpty) {
      return '$city — $locMerged';
    }
    if (city.isNotEmpty) return city;
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

  /// لا نعرض رقم المالك في مسارات المسوّق؛ التواصل عبر المسوّق/الترخيص فقط.
  String _marketingOwnerPhone(Map<String, dynamic> _) {
    return '';
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

  Widget _buildMarketingPriceLine(
    Map<String, dynamic> r, {
    required TextStyle style,
  }) {
    final isAuction = r['preview_is_auction'] == true;
    final currency = (r['preview_currency'] ?? 'SAR').toString().trim();
    final curr = currency.isEmpty ? 'SAR' : currency;
    final previewPrice = (r['preview_price'] as num?)?.toDouble() ?? 0.0;
    final requestPrice = (r['request_price'] as num?)?.toDouble() ?? 0.0;
    final rowPrice = (r['price'] is num) ? (r['price'] as num).toDouble() : 0.0;
    final currentBid = (r['preview_current_bid'] as num?)?.toDouble() ?? 0.0;
    final value = isAuction
        ? currentBid
        : (previewPrice > 0
            ? previewPrice
            : (requestPrice > 0
                ? requestPrice
                : (rowPrice > 0 ? rowPrice : 0.0)));

    if (value <= 0) {
      return Text(
        widget.isAr ? 'السعر غير محدد' : 'Price not set',
        style: style,
      );
    }
    return AppMoneyLine(
      amount: AppMoney.roundSar(value, fractionDigits: 0),
      currencyCode: curr,
      isAr: widget.isAr,
      maxFractionDigits: 0,
      style: style,
    );
  }

  List<Widget> _marketingPropertyChips(Map<String, dynamic> r) {
    final chips = <Widget>[];

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

  /// شبكة «صفحتي»: عمودان في الصف على الشاشات العادية (راحة قراءة).
  bool _useGridLayout(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 300;
  }

  /// عمودان ثابتان لصفوف «صفحتي» (إعلانان لكل صف).
  int _hubPropertyCrossAxisCount(double width) => 2;

  Widget _buildOwnerMarketingRequestsFeed(
    List<Map<String, dynamic>> requestRows,
  ) {
    final useGrid = _useGridLayout(context);
    if (!useGrid) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: requestRows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _buildOwnerListingRequestCard(
          requestRows[i],
          horizontalLayout: true,
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
          padding: EdgeInsets.symmetric(horizontal: padH),
          physics: const AlwaysScrollableScrollPhysics(),
          children: rows,
        );
      },
    );
  }

  double _marketerHubScrollBottomPadding(BuildContext context) {
    return MediaQuery.viewPaddingOf(context).bottom + 76;
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

    final ok = await _pushBody<bool>(
      CupertinoPageRoute<bool>(
        builder: (_) => MarketerRequestDetailsPage(
          lang: widget.lang,
          inviteId: inviteId,
          requestId: requestId,
        ),
      ),
    );

    if (ok == true && mounted) {
      await _loadMarketerBuckets(force: true);
    }
  }

  List<Widget> _marketerContractActionWidgets(Map<String, dynamic> r) {
    final ar = widget.isAr;
    final cid = (r['id'] ?? '').toString().trim();
    if (cid.isEmpty) return const [];
    final mid = (r['marketer_id'] ?? '').toString().trim();
    if (mid != _uid) return const [];

    final st = (r['status'] ?? '').toString().toLowerCase().trim();
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
        final reason = (r['returned_reason'] ?? '').toString().trim();
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
        content: TextField(
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
      await _loadMarketerBuckets(force: true);
    } catch (e) {
      if (!mounted) return;
      _showNotification(ar ? 'خطأ' : 'Error', e.toString(), isError: true);
    }
  }

  Future<void> _rpcSendListingContractToOwner(String contractId) async {
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
      await _loadMarketerBuckets(force: true);
    } catch (e) {
      if (!mounted) return;
      _showNotification(
        ar ? 'خطأ' : 'Error',
        e.toString(),
        isError: true,
      );
    }
  }

  Future<void> _createMarketingContract(Map<String, dynamic> row) async {
    final requestId = _marketingRequestIdFromRow(row);
    final ownerId =
        (row['request_owner_id'] ?? row['owner_id'] ?? '').toString().trim();
    final previewPropertyId =
        (row['preview_property_id'] ?? '').toString().trim();
    final offerId = (row['selected_offer_id'] ?? '').toString().trim();

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
    final permitId = (row['id'] ?? '').toString().trim();
    final requestId = _marketingRequestIdFromRow(row);
    final ownerId =
        (row['request_owner_id'] ?? row['owner_id'] ?? '').toString().trim();
    final previewPropertyId =
        (row['preview_property_id'] ?? '').toString().trim();
    if (requestId.isEmpty) return;

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

    Map<String, dynamic>? imported;
    if (kIsWeb) {
      imported = await showRegaElanImportWebDialog(
        context,
        isAr: widget.isAr,
      );
    } else {
      imported = await _pushBody<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => RegaAdLicenseImportPage(isAr: widget.isAr),
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

      _showNotification(
        widget.isAr ? 'تم' : 'Done',
        widget.isAr
            ? 'تم ربط بيانات ترخيص الإعلان مع الهيئة وحفظها في الإعلان.'
            : 'REGA ad license data linked and saved to the listing.',
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

  Future<void> _publishMarketingListingFromRow(Map<String, dynamic> row) async {
    final requestId = _marketingRequestIdFromRow(row);
    if (requestId.isEmpty) return;
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
        ListingWorkflowCopy.snackPublishedFromContract(widget.isAr),
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

    Property? p = _propertyCache[previewPropertyId];

    try {
      p ??= _all.firstWhere((e) => e.id == previewPropertyId);
    } catch (_) {}

    try {
      p ??= _mine.firstWhere((e) => e.id == previewPropertyId);
    } catch (_) {}

    p ??= await _fetchPropertyById(previewPropertyId);

    if (!mounted) return;

    if (p != null) {
      _applyUpdatedPropertyToCollections(p);
      await _openDetails(
        p,
        marketingRequestId: requestId.isEmpty ? null : requestId,
        marketingInviteId:
            (type == 'invite' && inviteId.isNotEmpty) ? inviteId : null,
        allowMarketingOffer: type == 'invite' && requestId.isNotEmpty,
        marketerHubPhase:
            const {'invite', 'offer', 'contract'}.contains(type) ? type : null,
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
    final selOffer = (r['selected_offer_id'] ?? '').toString().trim();
    if (selOffer.isEmpty) return false;
    final selMk = (r['selected_marketer_id'] ?? '').toString().trim();
    if (selMk.isNotEmpty && selMk != _uid) return false;
    return true;
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
      return 'قيمة العقار (الأساس): ${fmt.format(propertyBaseSar)} $riyal\n'
          'ضريبة 5٪ على العقار: ${fmt.format(pv)} $riyal\n'
          'المجموع: ${fmt.format(sub)} $riyal\n'
          'أتعاب التسويق $pct من المجموع: ${fmt.format(fee)} $riyal\n'
          'إجمالي مستحق: ${fmt.format(t)} $riyal';
    }
    return 'Property base: ${fmt.format(propertyBaseSar)} SAR\n'
        '5% VAT on property: ${fmt.format(pv)} SAR\n'
        'Subtotal: ${fmt.format(sub)} SAR\n'
        'Marketing fee $pct: ${fmt.format(fee)} SAR\n'
        'Total due: ${fmt.format(t)} SAR';
  }

  Future<void> _showMarketingOfferSheetForRow(Map<String, dynamic> row) async {
    final requestId = _marketingRequestIdFromRow(row);
    if (requestId.isEmpty) return;
    final hubKind =
        (row['_hubKind'] ?? row['_ui_type'] ?? '').toString().trim();
    final inviteIdRaw = (row['id'] ?? '').toString().trim();
    final base = _propertyBaseSarForMarketingFee(row);
    await showMarketingOfferSubmitSheet(
      context,
      requestId: requestId,
      inviteId: hubKind == 'invite' ? inviteIdRaw : null,
      isAr: widget.isAr,
      propertyBaseSarHint: (base != null && base > 0) ? base : null,
      onAfterSubmit: () => _loadMarketerBuckets(force: true),
    );
  }

  /// تتبع لحظي من الخادم: دعوات، عروض، عقود، طلب محدّث، عقار مرتبط.
  void _showOwnerRequestActivityDialog(Map<String, dynamic> row) {
    final id = (row['request_id'] ?? row['id'] ?? '').toString().trim();
    if (id.isEmpty) return;
    final ar = widget.isAr;
    final future = MarketingFlowService(_sb).ownerRequestActivityBundle(id);

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return AlertDialog(
              content: SizedBox(
                width: 300,
                height: 160,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppLogoLoading(),
                      const SizedBox(height: 16),
                      Text(
                        ar ? 'جارٍ تحميل التتبع...' : 'Loading activity…',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          if (snap.hasError) {
            return AlertDialog(
              title: Text(ar ? 'تعذر التحميل' : 'Failed to load'),
              content: SingleChildScrollView(
                child: Text('${snap.error}'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text(ar ? 'إغلاق' : 'Close'),
                ),
              ],
            );
          }
          final bundle = snap.data!;
          return AlertDialog(
            title: Text(ar ? 'تتبع نشاط الطلب' : 'Request activity'),
            content: SingleChildScrollView(
              child: _buildOwnerTrackingDialogContent(bundle, row, ar),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  showOwnerMarketingScenarioSheet(
                    context,
                    lang: widget.lang,
                    linkedRequestId: id,
                  );
                },
                child: Text(
                  AppLocalizations.of(context)!.workflowGuideDialogButton,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text(ar ? 'إغلاق' : 'Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOwnerTrackingDialogContent(
    Map<String, dynamic> bundle,
    Map<String, dynamic> fallbackRow,
    bool ar,
  ) {
    String fmt(dynamic v) {
      if (v == null) return '—';
      final s = v.toString();
      final dt = DateTime.tryParse(s);
      if (dt == null) return s;
      return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
    }

    String pick(dynamic v) => (v ?? '').toString().trim();

    String offerStatusLabel(String raw) {
      final s = raw.trim().toLowerCase();
      if (!ar) return raw.isEmpty ? '—' : raw;
      switch (s) {
        case 'submitted':
          return 'مُرسَل';
        case 'pending':
          return 'قيد الانتظار';
        case 'owner_accepted':
        case 'selected':
          return 'مقبول من المالك';
        case 'rejected':
        case 'owner_rejected':
          return 'مرفوض';
        case 'withdrawn':
          return 'مسحوب';
        case 'converted_to_contract':
          return 'حُوِّل لعقد';
        default:
          return raw.isEmpty ? '—' : raw;
      }
    }

    String inviteStatusLabel(String raw) {
      final s = raw.trim().toLowerCase();
      if (!ar) return raw.isEmpty ? '—' : raw;
      switch (s) {
        case 'invited':
          return 'مُرسَل للمسوّق';
        case 'seen':
          return 'اطّلع المسوّق / جارٍ المعالجة';
        case 'declined':
          return 'مرفوض من المسوّق';
        case 'expired':
          return 'منتهٍ';
        case 'offered':
          return 'قُدِّم عرض';
        default:
          return raw.isEmpty ? '—' : raw;
      }
    }

    String contractStatusLabel(String raw) {
      final s = raw.trim().toLowerCase();
      if (!ar) return raw.isEmpty ? '—' : raw;
      switch (s) {
        case 'draft':
          return 'مسودة';
        case 'pending_marketer':
          return 'بانتظار المسوّق';
        case 'pending_owner':
          return 'بانتظارك';
        case 'signed':
          return 'موقّع';
        case 'cancelled':
          return 'ملغى';
        default:
          return raw.isEmpty ? '—' : raw;
      }
    }

    final req = (bundle['request'] as Map<String, dynamic>?) ?? fallbackRow;
    final offers = ((bundle['offers'] as List?) ?? const <dynamic>[])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final invites = ((bundle['invites'] as List?) ?? const <dynamic>[])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final contracts = ((bundle['contracts'] as List?) ?? const <dynamic>[])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final linked = bundle['linkedProperty'] as Map<String, dynamic>?;

    Widget sectionTitle(String t) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(
            t,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        );

    Widget line(String label, String value) {
      final cs = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 360;
            final labelWidget = Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
                color: cs.onSurfaceVariant,
              ),
            );
            final valueWidget = SelectableText(
              value.isEmpty ? '—' : value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            );
            final box = DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 132, child: labelWidget),
                          const SizedBox(width: 10),
                          Expanded(child: valueWidget),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          labelWidget,
                          const SizedBox(height: 4),
                          valueWidget,
                        ],
                      ),
              ),
            );
            return box;
          },
        ),
      );
    }

    final children = <Widget>[
      Text(
        ar ? 'ملخص الطلب (محدّث من الخادم)' : 'Request summary (from server)',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      line(ar ? 'إنشاء الطلب' : 'Created', fmt(req['created_at'])),
      line(ar ? 'آخر تحديث' : 'Last update', fmt(req['updated_at'])),
      line(
        ar ? 'مرحلة سير العمل' : 'Workflow',
        pick(req['workflow_stage']).isEmpty ? '—' : pick(req['workflow_stage']),
      ),
      line(
        ar ? 'حالة الطلب' : 'Status',
        pick(req['status']).isEmpty ? '—' : pick(req['status']),
      ),
      line(
        ar ? 'أول دخول لك لصفحة العروض' : 'First offers-page view',
        req['owner_viewed_offers_at'] != null
            ? fmt(req['owner_viewed_offers_at'])
            : (ar
                ? 'لم يُسجَّل بعد — افتح «مراجعة عروض المسوقين» لتسجيله.'
                : 'Not recorded yet.'),
      ),
      line(
        ar ? 'المسوّق المختار' : 'Selected marketer',
        pick(req['selected_marketer_id']).isEmpty
            ? (ar ? 'لم يُحدَّد بعد' : 'Not set')
            : pick(req['selected_marketer_id']),
      ),
      line(ar ? 'بدء العقد' : 'Contract started',
          fmt(req['contract_started_at'])),
      line(ar ? 'إرسال العقد' : 'Contract sent', fmt(req['contract_sent_at'])),
      line(ar ? 'توقيع العقد' : 'Contract signed',
          fmt(req['contract_signed_at'])),
      line(
        ar ? 'انتظار المسوّقين منذ' : 'Waiting marketers since',
        fmt(req['waiting_marketers_since']),
      ),
    ];

    if (invites.isNotEmpty) {
      children
          .add(sectionTitle(ar ? 'سجل السوق والدعوات' : 'Market & invites'));
      for (var i = 0; i < invites.length; i++) {
        final inv = invites[i];
        final disp = pick(inv['_marketer_display_name']);
        final name = disp.isEmpty ? pick(inv['marketer_id']) : disp;
        final mPhone = pick(inv['_marketer_phone']);
        final mAcct = pick(inv['_marketer_account_type']);
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ar ? 'دعوة ${i + 1}: $name' : 'Invite ${i + 1}: $name',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    if (mPhone.isNotEmpty)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              ar ? 'الجوال: $mPhone' : 'Phone: $mPhone',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: ar ? 'نسخ الجوال' : 'Copy phone',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 30,
                              height: 30,
                            ),
                            padding: EdgeInsets.zero,
                            iconSize: 16,
                            icon: const Icon(Icons.copy_rounded),
                            onPressed: () => _copyPlainToClipboard(
                              mPhone,
                              ar ? 'تم نسخ رقم الجوال' : 'Phone copied',
                            ),
                          ),
                        ],
                      ),
                    if (mAcct.isNotEmpty)
                      Text(ar ? 'نوع الحساب: $mAcct' : 'Account: $mAcct'),
                    Text(
                      ar
                          ? 'المعرّف: ${pick(inv['marketer_id'])}'
                          : 'User ID: ${pick(inv['marketer_id'])}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ar
                          ? 'الحالة: ${inviteStatusLabel(pick(inv['status']))}'
                          : 'Status: ${pick(inv['status']).isEmpty ? '—' : pick(inv['status'])}',
                    ),
                    Text(
                        '${ar ? 'أُنشئت' : 'Created'}: ${fmt(inv['created_at'])}'),
                    Text(
                        '${ar ? 'آخر تحديث' : 'Updated'}: ${fmt(inv['updated_at'])}'),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    if (offers.isNotEmpty) {
      children.add(sectionTitle(ar ? 'عروض المسوّقين' : 'Marketer offers'));
      for (var i = 0; i < offers.length; i++) {
        final o = offers[i];
        final oDisp = pick(o['_marketer_display_name']);
        final name = oDisp.isEmpty ? pick(o['marketer_id']) : oDisp;
        final oPhone = pick(o['_marketer_phone']);
        final price = o['price'];
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ar ? 'عرض ${i + 1}: $name' : 'Offer ${i + 1}: $name',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    if (oPhone.isNotEmpty)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              ar ? 'الجوال: $oPhone' : 'Phone: $oPhone',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: ar ? 'نسخ الجوال' : 'Copy phone',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 30,
                              height: 30,
                            ),
                            padding: EdgeInsets.zero,
                            iconSize: 16,
                            icon: const Icon(Icons.copy_rounded),
                            onPressed: () => _copyPlainToClipboard(
                              oPhone,
                              ar ? 'تم نسخ رقم الجوال' : 'Phone copied',
                            ),
                          ),
                        ],
                      ),
                    Text(
                      ar
                          ? 'المعرّف: ${pick(o['marketer_id'])}'
                          : 'User ID: ${pick(o['marketer_id'])}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ar
                          ? 'الحالة: ${offerStatusLabel(pick(o['status']))}'
                          : 'Status: ${pick(o['status']).isEmpty ? '—' : pick(o['status'])}',
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text('${ar ? 'المبلغ' : 'Amount'}: '),
                          if (price is num)
                            AppMoneyLine(
                              amount: price.toDouble(),
                              currencyCode: 'SAR',
                              isAr: ar,
                              maxFractionDigits: 0,
                              style: const TextStyle(fontSize: 13),
                            )
                          else
                            Text(pick(price.toString())),
                        ],
                      ),
                    ),
                    Text(
                        '${ar ? 'أُرسل' : 'Submitted'}: ${fmt(o['created_at'])}'),
                    if (o['owner_responded_at'] != null)
                      Text(
                        '${ar ? 'ردك/النظام' : 'Owner response'}: ${fmt(o['owner_responded_at'])}',
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    if (contracts.isNotEmpty) {
      children.add(sectionTitle(ar ? 'العقود' : 'Contracts'));
      for (var i = 0; i < contracts.length; i++) {
        final c = contracts[i];
        final name = pick(c['_marketer_display_name']).isEmpty
            ? pick(c['marketer_id'])
            : pick(c['_marketer_display_name']);
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ar ? 'عقد ${i + 1}: $name' : 'Contract ${i + 1}: $name',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ar
                          ? 'الحالة: ${contractStatusLabel(pick(c['status']))}'
                          : 'Status: ${pick(c['status']).isEmpty ? '—' : pick(c['status'])}',
                    ),
                    Text(
                        '${ar ? 'أُنشئ' : 'Created'}: ${fmt(c['created_at'])}'),
                    Text(
                        '${ar ? 'إرسال للمالك' : 'Sent to owner'}: ${fmt(c['sent_at'])}'),
                    Text(
                        '${ar ? 'توقيع المالك' : 'Owner signed'}: ${fmt(c['owner_signed_at'])}'),
                    Text(
                      '${ar ? 'توقيع المسوّق' : 'Marketer signed'}: ${fmt(c['marketer_signed_at'])}',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    if (linked != null && pick(linked['id'] ?? linked['title']).isNotEmpty) {
      children.add(sectionTitle(ar ? 'عقار مرتبط' : 'Linked listing'));
      children.add(
        line(
          ar ? 'العنوان / المدينة' : 'Title / city',
          '${pick(linked['title'])} — ${pick(linked['city'])}',
        ),
      );
      final code = pick(linked['listing_public_code']);
      if (code.isNotEmpty) {
        children.add(line(ar ? 'رمز الإعلان' : 'Public code', code));
      }
    }

    if (invites.isEmpty && offers.isEmpty && contracts.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            ar
                ? 'لا توجد دعوات أو عروض أو عقود مسجّلة بعد لهذا الطلب.'
                : 'No invites, offers, or contracts recorded yet.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  void _showMarketerOfferTrackDialog(Map<String, dynamic> r) {
    final rid = _marketingRequestIdFromRow(r);
    final type = (r['_hubKind'] ?? r['_ui_type'] ?? '').toString();
    final isContract = type == 'contract' ||
        (r['sent_at'] ?? r['owner_signed_at'] ?? r['marketer_signed_at']) !=
            null;
    final created = r['created_at'];
    final responded = r['owner_responded_at'];
    final ownerViewed = r['owner_viewed_offers_at'];
    final sentAt = r['sent_at'] ?? r['contract_sent_at'];
    final ownerSignedAt = r['owner_signed_at'];
    final marketerSignedAt = r['marketer_signed_at'];
    final returnedAt = r['returned_at'];
    String fmt(dynamic v) {
      if (v == null) return '—';
      final s = v.toString();
      final dt = DateTime.tryParse(s);
      if (dt == null) return s;
      return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
    }

    Widget trackLine(String label, String value) {
      return LayoutBuilder(
        builder: (context, c) {
          final cs = Theme.of(context).colorScheme;
          final wide = c.maxWidth >= 360;
          final labelWidget = Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
              color: cs.onSurfaceVariant,
            ),
          );
          final valueWidget = SelectableText(
            value.trim().isEmpty ? '—' : value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 132, child: labelWidget),
                          const SizedBox(width: 10),
                          Expanded(child: valueWidget),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          labelWidget,
                          const SizedBox(height: 4),
                          valueWidget,
                        ],
                      ),
              ),
            ),
          );
        },
      );
    }

    final rows = <Widget>[
      trackLine(
        isContract
            ? (widget.isAr ? 'إنشاء العقد' : 'Contract created')
            : (widget.isAr ? 'إرسال العرض' : 'Offer submitted'),
        fmt(created),
      ),
      trackLine(
        isContract
            ? (widget.isAr ? 'إرسال العقد للمالك' : 'Contract sent to owner')
            : (widget.isAr ? 'أول مشاهدة للمالك' : 'Owner first viewed offers'),
        isContract
            ? (sentAt != null
                ? fmt(sentAt)
                : (widget.isAr
                    ? 'لم يُرسل العقد للمالك بعد.'
                    : 'Contract has not been sent to owner yet.'))
            : ownerViewed != null
                ? fmt(ownerViewed)
                : (widget.isAr ? 'لا يوجد سجل بعد.' : 'No record yet.'),
      ),
      trackLine(
        isContract
            ? (widget.isAr ? 'توقيع المالك' : 'Owner signature')
            : (widget.isAr ? 'استجابة المالك' : 'Owner response'),
        isContract
            ? (ownerSignedAt != null
                ? fmt(ownerSignedAt)
                : returnedAt != null
                    ? (widget.isAr
                        ? 'أُعيد للتعديل: ${fmt(returnedAt)}'
                        : 'Returned for revision: ${fmt(returnedAt)}')
                    : (widget.isAr
                        ? 'لم يوقّع المالك بعد.'
                        : 'Owner has not signed yet.'))
            : responded != null
                ? fmt(responded)
                : (widget.isAr
                    ? 'لا يوجد سجل استجابة بعد.'
                    : 'No owner response timestamp yet.'),
      ),
      if (isContract)
        trackLine(
          widget.isAr ? 'توقيع المسوق' : 'Marketer signature',
          marketerSignedAt != null
              ? fmt(marketerSignedAt)
              : (widget.isAr
                  ? 'لم يوقّع المسوق بعد.'
                  : 'Marketer has not signed yet.'),
        ),
      if (returnedAt != null)
        trackLine(widget.isAr ? 'آخر إعادة للتعديل' : 'Last returned',
            fmt(returnedAt)),
      if (rid.isNotEmpty)
        trackLine(widget.isAr ? 'رقم الطلب' : 'Request ID', rid),
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isContract
              ? (widget.isAr ? 'تتبع العقد' : 'Contract tracking')
              : (widget.isAr ? 'تتبع العرض' : 'Offer tracking'),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isAr
                      ? 'كل سطر يعرض العنوان والتفصيل من سجلات النظام.'
                      : 'Each row shows the activity label and system detail.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 10),
                ...rows,
              ],
            ),
          ),
        ),
        actions: [
          if (rid.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                showMarketingFullScenarioSheet(
                  context,
                  lang: widget.lang,
                  linkedRequestId: rid,
                );
              },
              child: Text(
                AppLocalizations.of(context)!.workflowGuideDialogButton,
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(widget.isAr ? 'إغلاق' : 'Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openOwnerListingRequestFromRow(
    Map<String, dynamic> row, {
    required String requestStatusId,
  }) async {
    if (requestStatusId.trim().isNotEmpty) {
      await _pushBody<void>(
        MaterialPageRoute<void>(
          builder: (_) => ListingRequestStatusPage(
            requestId: requestStatusId,
            lang: widget.lang,
          ),
        ),
      );
      if (!mounted) return;
      await _loadOwnerRequestsBuckets(force: true);
      await _loadMineAndOffers(force: true);
      return;
    }

    final previewPid = (row['preview_property_id'] ?? '').toString().trim();
    if (previewPid.isNotEmpty) {
      Property? p = _propertyCache[previewPid];
      try {
        p ??= _all.firstWhere((e) => e.id == previewPid);
      } catch (_) {}
      try {
        p ??= _mine.firstWhere((e) => e.id == previewPid);
      } catch (_) {}
      p ??= await _fetchPropertyById(previewPid);
      if (!mounted) return;
      if (p != null) {
        _applyUpdatedPropertyToCollections(p);
        await _openDetails(
          p,
          marketingRequestId: requestStatusId,
          allowMarketingOffer: false,
        );
        return;
      }
    }
    try {
      final data = await _sb
          .from('properties')
          .select('*')
          .eq('request_id', requestStatusId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (!mounted) return;
      if (data != null) {
        final p = Property.fromJson(Map<String, dynamic>.from(data));
        await _openDetails(
          p,
          marketingRequestId: requestStatusId,
          allowMarketingOffer: false,
        );
        return;
      }
    } catch (_) {}

    if (!mounted) return;
    await _pushBody<void>(
      MaterialPageRoute<void>(
        builder: (_) => ListingRequestStatusPage(
          requestId: requestStatusId,
          lang: widget.lang,
        ),
      ),
    );
    if (mounted) _loadOwnerRequestsBuckets(force: true);
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
      await _openDetails(
        p,
        marketingRequestId: requestId,
        marketingInviteId:
            hk == 'invite' ? (row['id'] ?? '').toString().trim() : null,
        allowMarketingOffer: hk == 'invite',
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
  }) {
    final vid = (videoStoragePath ?? '').trim();
    final showVideoLead =
        vid.isNotEmpty && (imageUrls.isEmpty || coverPrefersVideo);
    if (imageUrls.isNotEmpty || showVideoLead) {
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
          if (views != null && views >= 0)
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

  Widget _buildOwnerPublishedPropertiesList({
    required List<Property> items,
    required String emptyText,
  }) {
    if (_loadingMine && items.isEmpty) {
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

    final l10n = AppLocalizations.of(context)!;

    Widget publishedTile(int i, {required bool listLike}) {
      final p = items[i];
      final isGuest = _isGuest;
      final uid = _uid.isEmpty ? 'guest' : _uid;
      final isOwner = p.ownerId == uid;
      final allowCart = ListingPermissionsHelper.canAddToCart(
        property: p,
        currentUserId: isGuest ? null : uid,
        isGuest: isGuest,
        showCartNavSlot: _cartReservationFeaturesEnabled,
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _RealEstateCard(
            property: p,
            isOwner: isOwner,
            isAr: widget.isAr,
            bankColor: _brandPrimary,
            favorite: !isGuest && _isFav(p.id),
            onToggleFav:
                isGuest ? () => _showLoginDialog() : () => _toggleFav(p.id),
            onOpenDetails: () => _openDetails(p),
            activeCartHoldsCount: _activeReservationHoldCount(p.id),
            isReserved: _isReservedByAnyone(p.id),
            reservedUntil: _reservedUntil(p.id),
            reservedByName: _reservedByName(p.id),
            onAddToCart:
                (_cartReservationFeaturesEnabled && !isOwner && allowCart)
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
            forceListLayout: listLike,
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
          ),
          if (p.effectiveWorkflowStage != ListingWorkflowStage.published)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: ListingWorkflowProgressStrip(
                stage: p.effectiveWorkflowStage,
                compact: false,
                dense: true,
                deadline: p.reservationExpiresAt ?? p.permitDeadlineAt,
              ),
            ),
          Builder(
            builder: (ctx) {
              final rejectReason = _ownerRejectionReason(p);
              if (rejectReason == null || rejectReason.trim().isEmpty) {
                return const SizedBox.shrink();
              }
              final cs = Theme.of(ctx).colorScheme;
              return Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.error.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: cs.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l10n.ownerOfferRejectionReason(rejectReason),
                          style: TextStyle(
                            color: cs.error,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final useGrid = _useGridLayout(context);
        final paddingH = w >= 900 ? 18.0 : 12.0;

        if (!useGrid) {
          return ListView.separated(
            key: ValueKey<String>(
                'owner_pub_list_${items.length}_${emptyText.hashCode}'),
            padding: EdgeInsets.fromLTRB(paddingH, 12, paddingH, 12),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => publishedTile(i, listLike: true),
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
                          ? publishedTile(start + j, listLike: true)
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
          physics: const AlwaysScrollableScrollPhysics(),
          children: rowChildren,
        );
      },
    );
  }

  String _marketerCardOwnerCaption(String ownerName, String ownerPhone) {
    final n = ownerName.trim();
    if (n.isNotEmpty) {
      return widget.isAr
          ? 'منشئ الإعلان / المالك: $n'
          : 'Listing creator / owner: $n';
    }
    final ph = ownerPhone.trim();
    if (ph.isNotEmpty) {
      return widget.isAr ? 'المعلن — $ph' : 'Advertiser — $ph';
    }
    return widget.isAr ? 'المعلن (المالك)' : 'Advertiser (owner)';
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
        padding: EdgeInsets.fromLTRB(
          8,
          4,
          8,
          12 + _marketerHubScrollBottomPadding(context),
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final row = rows[i];
          final rowType = (row['_hubKind'] as String?) ?? type;
          return _buildMarketerRowCard(
            row,
            type: rowType,
            compact: false,
            index: i,
            marketerInvitesTabLayout: marketerInvitesTabLayout,
          );
        },
      );
    } else {
      child = LayoutBuilder(
        builder: (context, c) {
          final cross = _hubPropertyCrossAxisCount(c.maxWidth);
          const spacing = 12.0;
          final bottom = 12 + _marketerHubScrollBottomPadding(context);
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
            physics: const AlwaysScrollableScrollPhysics(),
            children: rowWidgets,
          );
        },
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(
        key: ValueKey<String>(animKey),
        child: child,
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
      final label = widget.isAr ? 'تقديم عرض' : 'Submit offer';
      return FilledButton(
        onPressed: () {
          if (canSubmitOffer) {
            _showMarketingOfferSheetForRow(r);
            return;
          }
          _showNotification(
            ar ? 'تنبيه' : 'Notice',
            inviteOfferBlockMessage ??
                (ar
                    ? 'لا يمكن تقديم عرض لهذه الدعوة حالياً.'
                    : 'You cannot submit an offer for this invite right now.'),
            isError: false,
          );
        },
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          minimumSize: const Size(0, 48),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.edit_note_outlined, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    }

    Widget detailsBtn() {
      return OutlinedButton(
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
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          minimumSize: const Size(0, 48),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.visibility_outlined, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                detailsLabel,
                maxLines: 2,
                textAlign: TextAlign.center,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
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
  }) {
    final cs = Theme.of(context).colorScheme;
    final actions = <Widget>[];

    if (type == 'invite' && marketerInvitesTabLayout) {
      actions.add(
        _buildMarketerInviteActionsGrid(
          r,
          canSubmitOffer: canSubmitOffer,
          canViewDetails: requestId.isNotEmpty || previewPropertyId.isNotEmpty,
          inviteOfferBlockMessage: inviteOfferBlockMessage,
          inviteDetailsBlockMessage: inviteDetailsBlockMessage,
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
                        ? 'لا يمكن تقديم عرض لهذه الدعوة حالياً.'
                        : 'You cannot submit an offer for this invite right now.'),
                isError: false,
              );
            },
            icon: const Icon(Icons.edit_note_outlined),
            label: Text(widget.isAr ? 'تقديم عرض' : 'Submit offer'),
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
      if (type == 'contract' && requestId.isNotEmpty) {
        actions.add(
          OutlinedButton.icon(
            onPressed: () => _showMarketerOfferTrackDialog(r),
            icon: const Icon(Icons.manage_search_outlined),
            label: Text(widget.isAr ? 'تتبع العقد' : 'Track contract'),
          ),
        );
      }
      if (type == 'offer' && !_marketerRowHasContract(r)) {
        if (_marketerOfferAcceptedByOwner(r)) {
          actions.add(
            FilledButton.icon(
              onPressed: () => _createMarketingContract(r),
              icon: const Icon(Icons.description_outlined),
              label: Text(widget.isAr ? 'إنشاء عقد' : 'Create Contract'),
            ),
          );
        } else {
          actions.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                widget.isAr
                    ? 'بانتظار موافقة المالك على عرضك قبل إنشاء العقد.'
                    : 'Awaiting owner approval before creating the contract.',
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
        actions.add(
          OutlinedButton.icon(
            onPressed: () {
              final cid = (r['id'] ?? '').toString().trim();
              unawaited(_pushBody<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ListingContractChatPage(
                    contractId: cid,
                    lang: widget.lang,
                  ),
                ),
              ));
            },
            icon: const Icon(Icons.chat_outlined),
            label: Text(widget.isAr ? 'محادثة العقد' : 'Contract chat'),
          ),
        );
        actions.addAll(_marketerContractActionWidgets(r));
      }
      if (type == 'permit') {
        final canPublish = _workflowStageFromMarketerRow(r) ==
            ListingWorkflowStage.permitIssued;
        actions.addAll([
          FilledButton.icon(
            onPressed: statusRaw == 'submitted'
                ? null
                : () => _submitMarketingPermit(r),
            icon: const Icon(Icons.verified_outlined),
            label: Text(widget.isAr ? 'رفع التصريح' : 'Submit Permit'),
          ),
          OutlinedButton.icon(
            onPressed: () => _linkRegaAdLicenseWithAuthority(r),
            icon: const Icon(Icons.link_outlined),
            label: Text(widget.isAr
                ? 'ربط التصريح مع الهيئة'
                : 'Link permit with REGA'),
          ),
        ]);
        if (canPublish) {
          actions.add(
            FilledButton.icon(
              onPressed: () => _publishMarketingListingFromRow(r),
              icon: const Icon(Icons.public_outlined),
              label: Text(ListingWorkflowCopy.btnPublishAd(widget.isAr)),
            ),
          );
        }
        if ((r['contract_pdf_url'] ?? '').toString().trim().isNotEmpty) {
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
      if (previewPropertyId.isNotEmpty || type == 'published') {
        actions.add(
          OutlinedButton.icon(
            onPressed: () => unawaited(_openMarketingPreviewProperty(r)),
            icon: const Icon(Icons.open_in_new),
            label: Text(widget.isAr ? 'فتح الإعلان' : 'Open Listing'),
          ),
        );
      }
    }

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
            if (type != 'permit' || n <= 0) return const SizedBox.shrink();
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
        Padding(
          padding: EdgeInsets.only(top: actions.isEmpty ? 0 : 8),
          child: ListingWorkflowProgressStrip(
            stage: _workflowStageFromMarketerRow(r),
            compact: true,
            dense: true,
            deadline: (r['permit_deadline_at'] ??
                        r['request_permit_deadline_at']) !=
                    null
                ? DateTime.tryParse(
                    (r['permit_deadline_at'] ?? r['request_permit_deadline_at'])
                        .toString(),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildSmartMarketerActionBar(List<Widget> actions) {
    if (actions.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // صف واحد حتى على الشاشات الضيقة: عمودان/ثلاثة أزرار بعرض متساوٍ دون تفاف النصوص.
        final horizontal = width >= 280 && actions.length <= 3;
        if (horizontal) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: actions[i]),
              ],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              actions[i],
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
  }) {
    final cs = Theme.of(context).colorScheme;
    final row = <String, dynamic>{...r, '_ui_type': type};

    final title = _mkRowTitle(row);
    final subLine = _mkRowSubLine(row);
    final typeLabel = _mkTypeLabel(type);
    final statusForDisplay = (type == 'invite' &&
            (r['invite_gate_status'] ?? '').toString().trim().isNotEmpty)
        ? r['invite_gate_status']?.toString()
        : r['status']?.toString();
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

    VoidCallback? onImageTap() {
      if (actions.canCardTap && canOpenMarketingDetails) {
        return () => unawaited(_openMarketingPreviewProperty(r));
      }
      if (actions.canSubmitOffer) {
        return () => _showMarketingOfferSheetForRow(r);
      }
      return null;
    }

    VoidCallback? bodyTapCallback() {
      if (actions.canCardTap && canOpenMarketingDetails) {
        return () => unawaited(_openMarketingPreviewProperty(r));
      }
      if (actions.canSubmitOffer) {
        return () => _showMarketingOfferSheetForRow(r);
      }
      return null;
    }

    final bt = bodyTapCallback();
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
    );

    return RepaintBoundary(
      child: Column(
        key: ValueKey<String>('marketer_${type}_$keyValue'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Card(
            elevation: 1.5,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: compact
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onImageTap(),
                          child: SizedBox(
                            width: double.infinity,
                            height: 190,
                            child: _buildMarketingPreviewImage(
                              previewImageUrls,
                              type: type,
                              views: previewViews,
                              videoStoragePath: previewVideoUrl.isEmpty
                                  ? null
                                  : previewVideoUrl,
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
                : IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onImageTap(),
                            child: SizedBox(
                              width: 132,
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(minHeight: 188),
                                child: _buildMarketingPreviewImage(
                                  previewImageUrls,
                                  type: type,
                                  views: previewViews,
                                  videoStoragePath: previewVideoUrl.isEmpty
                                      ? null
                                      : previewVideoUrl,
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
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: actionFooter,
          ),
        ],
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

    final descNorm = description.trim();
    final titleNorm = title.trim();
    final subNorm = subLine.trim();
    final locNorm = locationText.trim();
    final showDescription = descNorm.isNotEmpty &&
        descNorm != titleNorm &&
        descNorm != subNorm &&
        descNorm != locNorm &&
        !titleNorm.contains(descNorm) &&
        !subNorm.contains(descNorm);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 3,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              height: 1.25,
            ),
          ),
          Builder(
            builder: (ctx) {
              final src = previewPropertyId.trim().isNotEmpty
                  ? previewPropertyId
                  : requestId.trim();
              final code = DisplayIds.tenDigit(src);
              if (code.isEmpty) return const SizedBox.shrink();
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
          const SizedBox(height: 8),
          if (marketerEntityLine != null &&
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
                  child: Text(
                    widget.isAr
                        ? 'جهة التسويق: $marketerEntityLine'
                        : 'Marketing: $marketerEntityLine',
                    maxLines: 2,
                    softWrap: true,
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
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              if (ownerAvatarUrl.isNotEmpty)
                ClipOval(
                  child: Image.network(
                    ownerAvatarUrl,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.person_outline,
                      size: 16,
                      color: _brandPrimary,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.person_outline,
                  size: 16,
                  color: _brandPrimary,
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _marketerCardOwnerCaption(ownerName, ownerPhone),
                  maxLines: 3,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          if (ownerName.trim().isNotEmpty && ownerPhone.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.phone_outlined,
                  size: 16,
                  color: _brandPrimary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    ownerPhone,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: widget.isAr ? 'نسخ الجوال' : 'Copy phone',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () => _copyPlainToClipboard(
                    ownerPhone,
                    widget.isAr ? 'تم نسخ رقم الجوال' : 'Phone copied',
                  ),
                ),
              ],
            ),
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
                child: Text(
                  locationText,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subLine,
            maxLines: 3,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
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
              if (type == 'permit' &&
                  (r['contract_pdf_url'] ?? '').toString().trim().isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.09),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.green.withOpacity(0.28),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_outlined,
                        size: 15,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        widget.isAr
                            ? 'عقد PDF مُصدَّر'
                            : 'Exported contract PDF',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: Colors.green.shade800,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ..._marketingPropertyChips(r),
            ],
          ),
          const SizedBox(height: 10),
          if (!compact) const SizedBox(height: 12),
          const SizedBox(height: 14),
          FittedBox(
            alignment: AlignmentDirectional.centerStart,
            fit: BoxFit.scaleDown,
            child: _buildMarketingPriceLine(
              r,
              style: TextStyle(
                color: _brandPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                height: 1.25,
              ),
            ),
          ),
          Builder(
            builder: (_) {
              final base = _propertyBaseSarForMarketingFee(r);
              if (base == null ||
                  base <= 0 ||
                  (type != 'invite' && type != 'offer' && type != 'contract')) {
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
                                  ? 'لا يمكن تقديم عرض لهذه الدعوة حالياً.'
                                  : 'You cannot submit an offer for this invite right now.'),
                          isError: false,
                        );
                      },
                      icon: const Icon(Icons.edit_note_outlined),
                      label: Text(
                        widget.isAr ? 'تقديم عرض' : 'Submit offer',
                      ),
                    ),
                  if (type == 'offer' && requestId.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _showMarketerOfferTrackDialog(r),
                      icon: const Icon(Icons.timeline_outlined),
                      label: Text(widget.isAr ? 'تتبع' : 'Track'),
                    ),
                  if (type == 'offer' &&
                      (r['contract_id'] ?? '').toString().trim().isEmpty)
                    _marketerOfferAcceptedByOwner(r)
                        ? FilledButton.icon(
                            onPressed: () => _createMarketingContract(r),
                            icon: const Icon(Icons.description_outlined),
                            label: Text(
                              widget.isAr ? 'إنشاء عقد' : 'Create Contract',
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              widget.isAr
                                  ? 'بانتظار موافقة المالك على عرضك قبل إنشاء العقد.'
                                  : 'Awaiting owner approval before creating the contract.',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                                color: cs.primary,
                              ),
                            ),
                          ),
                  if (type == 'contract' &&
                      (r['id'] ?? '').toString().trim().isNotEmpty &&
                      _marketerContractFlowUnlocked(r)) ...[
                    if (requestId.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () {
                          unawaited(_pushBody<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => ListingRequestStatusPage(
                                requestId: requestId,
                                lang: widget.lang,
                              ),
                            ),
                          ));
                        },
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: Text(
                          widget.isAr ? 'العقد و PDF' : 'Contract & PDF',
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final cid = (r['id'] ?? '').toString().trim();
                        unawaited(_pushBody<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => ListingContractChatPage(
                              contractId: cid,
                              lang: widget.lang,
                            ),
                          ),
                        ));
                      },
                      icon: const Icon(Icons.chat_outlined),
                      label: Text(
                        widget.isAr ? 'محادثة العقد' : 'Contract chat',
                      ),
                    ),
                    ..._marketerContractActionWidgets(r),
                  ],
                  if (type == 'permit') ...[
                    FilledButton.icon(
                      onPressed: statusRaw == 'submitted'
                          ? null
                          : () => _submitMarketingPermit(r),
                      icon: const Icon(Icons.verified_outlined),
                      label: Text(
                        widget.isAr ? 'رفع التصريح' : 'Submit Permit',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _linkRegaAdLicenseWithAuthority(r),
                      icon: const Icon(Icons.link_outlined),
                      label: Text(
                        widget.isAr
                            ? 'ربط التصريح مع الهيئة'
                            : 'Link permit with REGA',
                      ),
                    ),
                    if ((r['contract_pdf_url'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => unawaited(_openContractPdfUrl(r)),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: Text(
                          widget.isAr ? 'فتح PDF العقد' : 'Open contract PDF',
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
                if (type == 'permit' && n > 0) {
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
                }
                return const SizedBox.shrink();
              },
            ),
          if (includeWorkflowProgress)
            Builder(
              builder: (_) {
                final st = _workflowStageFromMarketerRow(r);
                final pda =
                    r['permit_deadline_at'] ?? r['request_permit_deadline_at'];
                final dl =
                    pda != null ? DateTime.tryParse(pda.toString()) : null;
                return ListingWorkflowProgressStrip(
                  stage: st,
                  compact: true,
                  dense: true,
                  deadline: dl,
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
