part of 'user_dashboard.dart';

extension _UserDashboardStateActions on _UserDashboardState {
  // =========================
  // Navigation / actions
  // =========================

  /// يفتح فوق جذر اللوحة فقط (يُبقي AppBar + الشريط السفلي ظاهرين).
  Future<T?> _pushBody<T extends Object?>(Route<T> route) async {
    final nav = _dashboardBodyNavKey.currentState;
    if (nav == null) return null;
    return nav.push<T>(route);
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

  Future<void> _logout() async {
    if (_loggingOut) return;
    _ss(() => _loggingOut = true);

    final prefs = await SharedPreferences.getInstance();

    try {
      if (_isGuest) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
          '/login',
          (route) => false,
        );
        return;
      }

      // تجنب طلب /logout عندما لا توجد جلسة (يقلل 403 في الـ Network على الويب).
      if (_sb.auth.currentSession != null) {
        try {
          await _sb.auth.signOut(scope: SignOutScope.local);
        } catch (_) {
          try {
            await _sb.auth.signOut();
          } catch (_) {}
        }
      }

      InAppNotificationHub.setSessionUsername(null);
      InAppNotificationHub.setSessionUserId(null);
      InAppNotificationHub.dismiss();

      try {
        await FastLoginService.clearAll();
      } catch (_) {}

      try {
        await prefs.remove('guest_mode');
        await prefs.remove('entry_mode');
      } catch (_) {}

      _propertyCache.clear();
      _profileCache.clear();
      _favoriteIds.clear();
      _clearMarketingStateOnLogout();

      try {
        await resetStoredAppearanceForNextSignIn();
      } catch (_) {}

      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
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
    }
  }

  /// تبويب «إدارتي»: لوحة المنشأة/المسوّق/المعلن الفردي (منفصلة عن زر +).
  Future<void> _openMyDeskNav() async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }

    if (AppRoleHelper.isOrgEntity(_accountType)) {
      await _pushBody<void>(
        MaterialPageRoute<void>(
          builder: (_) => MyDeskOrgShellPage(lang: widget.lang),
        ),
      );
      if (!mounted) return;
      await _reloadAll();
      return;
    }

    if (AppRoleHelper.isStandaloneMarketer(_accountType)) {
      await _pushBody<void>(
        MaterialPageRoute<void>(
          builder: (_) => MarketerDashboardPage(lang: widget.lang),
        ),
      );
      if (!mounted) return;
      await _reloadAll();
      return;
    }

    if (AppRoleHelper.isOwnerIndividual(_accountType)) {
      await _pushBody<void>(
        MaterialPageRoute<void>(
          builder: (_) => OwnerIndividualDeskPage(
            lang: widget.lang,
            userId: _uid,
          ),
        ),
      );
      if (!mounted) return;
      await _reloadAll();
      return;
    }

    if (_orgNavIsOwner ||
        AppRoleHelper.orgPermissionsOpenDeskShell(_orgMembershipPermissions)) {
      final ctx = await OrgTeamService(_sb).myOrgContext();
      final oid = ctx?['org_id']?.toString();
      if (oid != null && oid.isNotEmpty) {
        await _pushBody<void>(
          MaterialPageRoute<void>(
            builder: (_) => MyDeskOrgShellPage(lang: widget.lang),
          ),
        );
        if (!mounted) return;
        await _reloadAll();
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
    unawaited(
      showMarketRequestHomeSheet(
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
      ),
    );
  }

  Future<void> _openMapDiscovery() async {
    AppHaptics.light();
    final properties = _all
        .where((p) => p.latitude != null && p.longitude != null)
        .toList(growable: false);
    final requests = _marketHomeRequests
        .where((r) => r.latitude != null && r.longitude != null)
        .toList(growable: false);

    await _pushBody<void>(
      MaterialPageRoute<void>(
        builder: (_) => PropertyMapDiscoveryPage(
          isAr: widget.isAr,
          properties: properties,
          requests: requests,
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
  Future<void> _openMarketRequestDetailById(String requestId) async {
    final rid = requestId.trim();
    if (rid.isEmpty) return;
    for (final e in _marketHomeRequests) {
      if (e.id == rid) {
        _openMarketRequestDetail(e);
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
      _openMarketRequestDetail(MarketPropertyRequestRow.fromMap(map));
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
        builder: (_) => CreateMarketPropertyRequestPage(
          userId: _uid,
          lang: widget.lang,
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
        builder: (_) => CreateMarketPropertyRequestPage(
          userId: _uid,
          lang: widget.lang,
          initialRequest: request,
        ),
      ),
    );
    if (!mounted) return;
    if (res == true) {
      await _reloadAll();
      if (mounted) _ss(() => _tabIndex = 2);
    }
  }

  /// زر + العائم: إعلان عقاري أو طلب عقاري (بدون دمج الشاشتين).
  Future<void> _openCenterPlus() async {
    if (_isGuest) {
      _showLoginDialog();
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

    if (!mounted) return;

    if (choice == 'request') {
      final res = await _pushBody<Object?>(
        MaterialPageRoute<Object?>(
          fullscreenDialog: true,
          builder: (_) => CreateMarketPropertyRequestPage(
            userId: _uid,
            lang: widget.lang,
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

    if (choice != 'listing') {
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
        ),
      ),
    );

    if (!mounted) return;

    if (res == true) {
      await _reloadAll();
      if (mounted) _ss(() => _tabIndex = 0);
    }
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
          onEditProperty: (prop) => _editProperty(prop),
          onRequestDelete: (prop) => _requestDeleteProperty(prop),
        ),
      ),
    );
  }

  void _openSupportPage() {
    unawaited(_pushBody<void>(
      MaterialPageRoute<void>(
        builder: (_) => SupportPage(
          userId: _uid,
          isAr: widget.isAr,
          bankColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    ));
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
                TextField(
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
      String? img;
      if (p.images.isNotEmpty) {
        final first = p.images.first.trim();
        if (first.startsWith('http://') || first.startsWith('https://')) {
          img = first;
        } else if (first.isNotEmpty) {
          try {
            img = _sb.storage.from('property-images').getPublicUrl(first);
          } catch (_) {}
        }
      }
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
        widget.isAr ? 'تم الحجز' : 'Reserved',
        widget.isAr ? 'تم الحجز لمدة 72 ساعة' : 'Reserved for 72 hours',
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
            title: Text(widget.isAr ? 'تقديم عرض' : 'Submit offer'),
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
                  TextField(
                    controller: priceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: latinDecimalNumberFormatters(),
                    decoration: InputDecoration(
                      labelText: widget.isAr
                          ? 'قيمة العرض (${AppMoney.saudiRiyalSignUnicode})'
                          : 'Offer amount (SAR)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: msgCtrl,
                    decoration: InputDecoration(
                      labelText: widget.isAr
                          ? 'رسالتك للمسوق (اختياري)'
                          : 'Message to marketer (optional)',
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
                child: Text(widget.isAr ? 'إرسال العرض' : 'Send offer'),
              ),
            ],
          );
        },
      );

      if (ok != true) return null;
      final parsedOfferPrice = NumberHelper.toDouble(priceCtrl.text.trim());
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
      _dashboardBodyNavKey.currentState?.popUntil((route) => route.isFirst);
      _ss(() => _tabIndex = 1);
      if (!_isMarketerRole && _ownerTabsCtrl != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final c = _ownerTabsCtrl;
          if (c != null && c.length > 6) {
            c.animateTo(6);
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
    final hp = await UserListingPreferencesService.hiddenPropertyIds();
    final hr = await UserListingPreferencesService.hiddenMarketRequestIds();
    final hc =
        await UserListingPreferencesService.hiddenCompletedDealPropertyIds();
    if (!mounted) return;
    setState(() {
      _hiddenPropertyIds = hp;
      _hiddenMarketRequestIds = hr;
      _hiddenCompletedDealPropertyIds = hc;
    });
  }

  Future<void> _copyPlainToClipboard(String text, String okMessage) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    _showNotification(
      widget.isAr ? 'تم النسخ' : 'Copied',
      okMessage,
    );
  }

  Future<void> _hideCompletedDealFromOwnerHub(String propertyId) async {
    final id = propertyId.trim();
    if (id.isEmpty) return;
    await UserListingPreferencesService.addHiddenCompletedDealProperty(id);
    if (!mounted) return;
    setState(() {
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

  Future<void> _restoreAllHiddenCompletedDeals() async {
    await UserListingPreferencesService.clearHiddenCompletedDeals();
    if (!mounted) return;
    setState(() => _hiddenCompletedDealPropertyIds = {});
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
          ),
        ),
      );
      if (!mounted) return;
      if (res == true) await _reloadAll();
      return;
    }

    final res = await _pushBody<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => addp.AddPropertyPage(
          userId: _uid,
          lang: widget.lang,
        ),
      ),
    );
    if (!mounted) return;
    if (res == true) await _reloadAll();
  }

  Future<void> _onHomeHideProperty(Property p) async {
    if (_isGuest) return;
    await UserListingPreferencesService.addHiddenProperty(p.id);
    if (!mounted) return;
    setState(() => _hiddenPropertyIds = {..._hiddenPropertyIds, p.id});
    final l10n = AppLocalizations.of(context);
    if (l10n != null) {
      _toast(l10n.dashboardToastListingHiddenFromHome);
    }
  }

  Future<void> _onRestorePropertyToHome(Property p) async {
    if (_isGuest) return;
    await UserListingPreferencesService.removeHiddenProperty(p.id);
    if (!mounted) return;
    setState(() {
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
    setState(() {
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
    setState(
        () => _hiddenMarketRequestIds = {..._hiddenMarketRequestIds, r.id});
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
}
