part of 'user_dashboard.dart';

// === ملف: user_dashboard.actions.dart ===
// الهدف: عمليات المستخدم (Navigation / Property actions / Reservation actions).
// يحتوي: فتح الصفحات/إضافة للسلة/حذف/تعديل/عمليات الحجوزات.

extension _UserDashboardStateActions on _UserDashboardState {
  // =========================
  // Navigation / actions
  // =========================

  void _readArgsInBuildOnce(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final l = args['lang'];
      if (l is String && l.isNotEmpty && l != _lang) {
        langNotifier.value = l;
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
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        return;
      }

      await _sb.auth.signOut();

      try {
        await fl_service.FastLoginService.clearAll();
      } catch (_) {}

      try {
        await prefs.remove(kPrefGuestMode);
        await prefs.remove(kPrefEntryMode);
      } catch (_) {}

      _propertyCache.clear();
      _profileCache.clear();
      _favoriteIds.clear();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        _showNotification(
          _isArabic ? 'خطأ' : 'Error',
          _isArabic ? 'تعذر تسجيل الخروج: $e' : 'Logout failed: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) _ss(() => _loggingOut = false);
    }
  }

  Future<void> _openAdd() async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }

    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => addp.AddPropertyPage(userId: _uid, lang: _lang),
      ),
    );

    if (!mounted) return;

    if (res == true) {
      await _reloadAll();
      if (mounted) _ss(() => _tabIndex = 1);
    }
  }

  void _openDetails(Property p) {
    final ownerForDetails = _isGuest ? null : p.ownerUsername;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => details.PropertyDetailsPage(
          property: p,
          isAr: _isArabic,
          currentUserId: _isGuest ? 'guest' : _uid,
          ownerUsername: ownerForDetails,
          isFavorite: !_isGuest && _isFav(p.id),
          onToggleFavorite: () async {
            if (_isGuest) {
              _showLoginDialog();
              return;
            }
            await _toggleFav(p.id);
          },
        ),
      ),
    );
  }

  // =========================
  // فتح صفحة الدعم الفني
  // =========================
  void _openSupportPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupportPage(
          userId: _uid,
          isAr: _isArabic,
          bankColor: _UserDashboardState._bankColor,
        ),
      ),
    );
  }

  // =========================
  // فتح صفحة الإشعارات
  // =========================
  void _openNotificationsPage() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isArabic ? 'الإشعارات' : 'Notifications'),
        content: SizedBox(
          width: double.maxFinite,
          child: _loadingNotifications
              ? const Center(child: CircularProgressIndicator())
              : _notifications.isEmpty
                  ? Text(_isArabic
                      ? 'لا توجد إشعارات جديدة'
                      : 'No new notifications')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _notifications.length,
                      itemBuilder: (context, index) {
                        final notif = _notifications[index];
                        final created = DateTime.tryParse(
                          (notif['created_at'] ?? '').toString(),
                        );

                        return ListTile(
                          leading: const Icon(Icons.notifications),
                          title: Text((notif['title'] ?? '').toString()),
                          subtitle: Text((notif['message'] ?? '').toString()),
                          trailing: Text(
                            created == null ? '' : _timeAgo(created, _isArabic),
                          ),
                        );
                      },
                    ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_isArabic ? 'إغلاق' : 'Close'),
          ),
        ],
      ),
    );
  }

  // =========================
  // Property actions
  // =========================

  Future<void> _editProperty(Property property) async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditPropertyPage(
          property: property,
          userId: _uid,
          lang: _lang,
        ),
      ),
    );

    if (!mounted) return;

    if (result is Property) {
      _ss(() {
        final i1 = _all.indexWhere((p) => p.id == result.id);
        if (i1 != -1) _all[i1] = result;

        final i2 = _mine.indexWhere((p) => p.id == result.id);
        if (i2 != -1) _mine[i2] = result;

        final i3 = _favoritesList.indexWhere((p) => p.id == result.id);
        if (i3 != -1) _favoritesList[i3] = result;

        if (result.id.isNotEmpty) {
          _propertyCache[result.id] = result;
          _myPropertyById[result.id] = result;
        }
      });

      _showNotification(
        _isArabic ? 'تم التحديث' : 'Updated',
        _isArabic ? 'تم تحديث الإعلان بنجاح' : 'Listing updated successfully',
      );
    }
  }

  // ✅ FIX: لا تترك _loadingMine يعلق (try/finally)
  Future<void> _deleteProperty(String propertyId) async {
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isArabic ? 'تأكيد الحذف' : 'Confirm Delete'),
        content: Text(
          _isArabic
              ? 'هل أنت متأكد من حذف هذا الإعلان؟ لا يمكن التراجع عن هذا الإجراء.'
              : 'Are you sure you want to delete this listing? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_isArabic ? 'إلغاء' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_isArabic ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    _ss(() => _loadingMine = true);
    try {
      await _sb.from('properties').delete().eq('id', propertyId);

      // تنظيف محلي سريع + حفظ المفضلة (إن كان محذوف ضمنها)
      _ss(() {
        _all.removeWhere((p) => p.id == propertyId);
        _mine.removeWhere((p) => p.id == propertyId);
        _favoritesList.removeWhere((p) => p.id == propertyId);
        _favoriteIds.remove(propertyId);

        _propertyCache.remove(propertyId);
        _myPropertyById.remove(propertyId);
        _activeReservationByPropertyId.remove(propertyId);
      });

      await _saveFavoritesForUid();

      if (mounted) {
        await _reloadAll();
        _showNotification(
          _isArabic ? 'تم الحذف' : 'Deleted',
          _isArabic ? 'تم حذف الإعلان بنجاح' : 'Property deleted successfully',
        );
      }
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        _showNotification(
          _isArabic ? 'خطأ' : 'Error',
          _isArabic ? 'فشل حذف الإعلان: $msg' : 'Failed to delete property: $msg',
          isError: true,
        );
      }
      // ignore: avoid_print
      print('deleteProperty error: $e');
    } finally {
      if (mounted) _ss(() => _loadingMine = false);
    }
  }

  // =========================
  // Reservation actions
  // =========================

  bool _isReservedByAnyone(String propertyId) {
    final r = _activeReservationByPropertyId[propertyId];
    if (r == null) return false;
    if (!_isStillValidReservationRow(r)) return false;
    final st = (r['status'] ?? '').toString();
    return st == 'active' || st == 'pending';
  }

  DateTime? _reservedUntil(String propertyId) {
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

  Future<void> _addToCart(Property p) async {
    if (_isGuest) {
      _showLoginDialog();
      return;
    }

    if (p.ownerId == _uid) {
      _showNotification(
        _isArabic ? 'غير مسموح' : 'Not Allowed',
        _isArabic ? 'لا يمكنك حجز إعلانك' : 'You cannot reserve your own listing',
        isError: true,
      );
      return;
    }

    if (_isReservedByAnyone(p.id)) {
      final ex = _reservedUntil(p.id);
      final txt = ex == null ? '' : _fmtDateTime(ex);
      _showNotification(
        _isArabic ? 'محجوز' : 'Reserved',
        _isArabic ? 'العقار محجوز حتى $txt' : 'Already reserved until $txt',
        isError: true,
      );
      return;
    }

    try {
      final double basePrice = p.isAuction ? (p.currentBid ?? p.price) : p.price;

      final ok = await ReservationsService.createReservation(
        userId: _uid,
        propertyId: p.id,
        basePrice: basePrice,
      );

      if (!ok) {
        if (!mounted) return;
        _showNotification(
          _isArabic ? 'محجوز' : 'Reserved',
          _isArabic ? 'هذا الإعلان محجوز بالفعل' : 'This listing is already reserved',
          isError: true,
        );
        return;
      }

      _propertyCache.clear();
      _profileCache.clear();

      await Future.wait([
        _loadCart(force: true),
        _loadHome(force: true),
        _loadMineAndOffers(force: true),
      ]);

      if (!mounted) return;

      _showNotification(
        _isArabic ? 'تمت الإضافة' : 'Added',
        _isArabic ? 'تمت الإضافة للسلة لمدة 72 ساعة' : 'Added to cart for 72 hours',
      );

      _ss(() => _tabIndex = 3);
    } catch (e) {
      final msg = e.toString();
      if (!mounted) return;
      _showNotification(
        _isArabic ? 'فشل الحجز' : 'Reservation Failed',
        _isArabic ? 'فشل الحجز: $msg' : 'Reservation failed: $msg',
        isError: true,
      );
    }
  }

  Future<void> _cancelReservationFromCart(Map<String, dynamic> r) async {
    final id = (r['id'] ?? '').toString();
    if (id.isEmpty) return;

    try {
      await _sb.from('reservations').update({'status': 'cancelled'}).eq('id', id);

      _propertyCache.clear();
      await Future.wait([
        _loadCart(force: true),
        _loadHome(force: true),
        _loadMineAndOffers(force: true),
      ]);

      if (!mounted) return;

      _showNotification(
        _isArabic ? 'تم الإلغاء' : 'Cancelled',
        _isArabic ? 'تم إلغاء الحجز' : 'Reservation cancelled',
      );
    } catch (e) {
      final msg = e.toString();
      _showNotification(
        _isArabic ? 'فشل الإلغاء' : 'Cancel Failed',
        _isArabic ? 'فشل الإلغاء: $msg' : 'Cancel failed: $msg',
        isError: true,
      );
    }
  }
}
