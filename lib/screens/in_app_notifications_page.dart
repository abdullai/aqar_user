// lib/screens/in_app_notifications_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/app_branding.dart';
import '../core/platform/viewport_scroll_policy.dart';
import '../core/l10n/locale_content.dart';
import '../core/utils/search_normalize.dart';
import '../core/notifications/in_app_notification_catalog.dart';
import '../core/input/locale_text_input_guard.dart';
import '../models.dart';
import '../l10n/app_localizations.dart';
import '../services/ads_service.dart';
import '../services/communication_hub_service.dart';
import '../services/in_app_notification_hub.dart';
import '../services/in_app_notification_router.dart';
import '../services/marketing_flow_service.dart';
import '../services/notification_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/inbox_bulk_toolbar.dart';
import '../widgets/inbox_surface_chrome.dart';
import '../widgets/swipe_actions_tile.dart';

class InAppNotificationsPage extends StatefulWidget {
  final String lang;

  /// بدون [Scaffold]/[AppBar] — للتضمين داخل مركز الإشعارات والمحادثات.
  final bool embedMode;

  /// يُستدعى بعد تحديث قائمة الصندوق (مثلاً لتحديث شارة تبويب «الإشعارات» في [CommunicationHubPage]).
  final VoidCallback? onInboxSurfaceChanged;

  /// تبويب إعلانات المنصة وحملات الدفع داخل مركز الجرس.
  final bool campaignsOnly;

  const InAppNotificationsPage({
    super.key,
    required this.lang,
    this.embedMode = false,
    this.onInboxSurfaceChanged,
    this.campaignsOnly = false,
  });

  @override
  State<InAppNotificationsPage> createState() => _InAppNotificationsPageState();
}

enum _NotifSort { recent, unreadFirst }

class _InAppNotificationsPageState extends State<InAppNotificationsPage>
    with SingleTickerProviderStateMixin {
  final _svc = MarketingFlowService(Supabase.instance.client);
  late final TabController _tabCtrl;
  final _inboxSearch = TextEditingController();

  bool _loading = true;
  String? _err;
  List<Map<String, dynamic>> _items = const [];
  List<AdItem> _hubAds = const [];
  bool _selectMode = false;
  bool _searchOpen = false;
  final Set<String> _selectedIds = {};
  _NotifSort _sort = _NotifSort.recent;

  bool _didMarkOpenedRead = false;

  String get _lang {
    final fromRoute =
        (ModalRoute.of(context)?.settings.arguments as Map?)?['lang'];
    if (fromRoute is String && fromRoute.trim().isNotEmpty) {
      return fromRoute.trim().toLowerCase() == 'en' ? 'en' : 'ar';
    }
    return widget.lang.toLowerCase() == 'en' ? 'en' : 'ar';
  }

  bool get _isAr => _lang != 'en';
  int get _archiveIndex => widget.campaignsOnly ? 1 : 3;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: widget.campaignsOnly ? 2 : 4,
      vsync: this,
      initialIndex: 0,
    )
      ..addListener(() {
        if (mounted) setState(() {});
      });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await NotificationService.clearOsApplicationIconBadge();
      } catch (_) {}
      if (mounted) await _load();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _inboxSearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final rows = await _svc.myInAppNotificationsInbox(includeArchived: true);
      final filtered = widget.campaignsOnly
          ? rows.where(MarketingFlowService.isOpsCampaignNotificationRow).toList()
          : rows
              .where((r) => !MarketingFlowService.isOpsCampaignNotificationRow(r))
              .toList();
      setState(() => _items = filtered);
      if (!_didMarkOpenedRead && filtered.isNotEmpty) {
        _didMarkOpenedRead = true;
        unawaited(_markOpenedInboxRead());
      }
      if (widget.campaignsOnly) {
        final ads = await AdsService.loadAds(
          lang: widget.lang,
          fallbackDemo: false,
        );
        if (mounted) setState(() => _hubAds = ads);
      }
    } catch (_) {
      if (!mounted) return;
      final en = widget.lang.toLowerCase() == 'en';
      setState(() => _err = en
          ? 'Could not load notifications. Check your connection and retry.'
          : 'تعذر تحميل الإشعارات. تحقق من الاتصال ثم أعد المحاولة.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (mounted) {
      widget.onInboxSurfaceChanged?.call();
      InAppNotificationHub.onInboxInvalidate?.call();
    }
  }

  Future<void> _markOpenedInboxRead() async {
    final unread = _items
        .where((e) => e['is_read'] != true)
        .map((e) => (e['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    if (unread.isEmpty) return;
    if (mounted) {
      setState(() {
        _items = [
          for (final e in _items) {...e, 'is_read': true},
        ];
      });
    }
    widget.onInboxSurfaceChanged?.call();
    InAppNotificationHub.onInboxInvalidate?.call();
    try {
      await CommunicationHubService.markAllNotificationsRead(
        Supabase.instance.client,
      );
    } catch (_) {}
    widget.onInboxSurfaceChanged?.call();
    InAppNotificationHub.onInboxInvalidate?.call();
  }

  Map<String, dynamic> _dataMap(Map<String, dynamic> row) {
    final raw = row['data'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return {};
  }

  /// 0=الكل، 1=تسويق/عقود، 2=أخرى — دردشة تُدار من تبويب المحادثات لا هنا.
  int _categoryForRow(Map<String, dynamic> n) {
    if (MarketingFlowService.isChatStyleNotificationRow(n)) return -1;
    final type = (n['type'] ?? '').toString().toLowerCase().trim();
    final data = _dataMap(n);
    final ent = (n['entity_type'] ?? data['entity_type'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    if (_isMarketingOrListingType(type, ent)) return 1;
    return 2;
  }

  bool _isMarketingOrListingType(String type, String ent) {
    if (ent == InAppEntityTypes.listingRequest ||
        ent == InAppEntityTypes.listingOffer ||
        ent == InAppEntityTypes.listingContract ||
        ent == InAppEntityTypes.listingPermit ||
        ent == InAppEntityTypes.property) {
      return true;
    }

    const known = <String>{
      InAppNotifTypes.workflow,
      InAppNotifTypes.offerSubmitted,
      InAppNotifTypes.offerReceived,
      InAppNotifTypes.offerAccepted,
      InAppNotifTypes.offerDeclined,
      InAppNotifTypes.contractCreated,
      InAppNotifTypes.contractPendingSignature,
      InAppNotifTypes.permitSubmitted,
      InAppNotifTypes.permitPackageSubmitted,
      InAppNotifTypes.listingPublished,
      InAppNotifTypes.listingRequestSubmitted,
      InAppNotifTypes.propertyCreated,
      InAppNotifTypes.reservation,
      InAppNotifTypes.photoShootRequested,
      InAppNotifTypes.photoShootAccepted,
      InAppNotifTypes.photoShootRejected,
      InAppNotifTypes.photoShootDelivered,
      InAppNotifTypes.photographerVerified,
      InAppNotifTypes.photographerRejected,
      InAppNotifTypes.photographerRated,
      'marketing_offer',
      'contract_signed',
      'permit_issued',
      'booking',
      'payment',
    };
    if (known.contains(type)) return true;
    if (type.startsWith('offer_')) return true;
    if (type.contains('contract')) return true;
    if (type.contains('permit')) return true;
    if (type.contains('listing')) return true;
    return false;
  }

  List<Map<String, dynamic>> _visibleItems() {
    final i = _tabCtrl.index;
    Iterable<Map<String, dynamic>> base;
    final archiveIndex = widget.campaignsOnly ? 1 : 3;
    if (i == archiveIndex) {
      base = _items.where(MarketingFlowService.isArchivedNotificationRow);
    } else {
      base = _items.where((n) {
        if (!MarketingFlowService.isVisibleInMainInbox(n)) return false;
        return !MarketingFlowService.isChatStyleNotificationRow(n);
      });
      if (!widget.campaignsOnly && i != 0) {
        base = base.where((n) => _categoryForRow(n) == i);
      }
    }
    final list = base.map((e) => Map<String, dynamic>.from(e)).toList();
    list.sort((a, b) {
      if (_sort == _NotifSort.unreadFirst) {
        final ua = _isUnread(a) ? 1 : 0;
        final ub = _isUnread(b) ? 1 : 0;
        if (ua != ub) return ub.compareTo(ua);
      }
      final ta = DateTime.tryParse((a['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse((b['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return list;
  }

  String _titleForRow(Map<String, dynamic> row) {
    final data = _dataMap(row);
    final picked = LocaleContent.pick(
      isAr: _isAr,
      ar: (data['title_ar'] ?? '').toString(),
      en: (data['title_en'] ?? '').toString(),
      fallback: (data['title'] ?? row['title'] ?? row['type'] ?? '').toString(),
    );
    return AppBranding.normalizeUserFacing(
      LocaleContent.forUi(picked, isAr: _isAr),
      isAr: _isAr,
    );
  }

  Widget _mediaThumb(String url) {
    final lower = url.toLowerCase();
    final isVideo = lower.contains('.mp4') ||
        lower.contains('.webm') ||
        lower.contains('.mov') ||
        lower.contains('video');
    if (isVideo) {
      return Row(
        children: [
          const Icon(Icons.play_circle_outline_rounded, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        height: 88,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Row(
          children: [
            const Icon(Icons.image_outlined, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isUnread(Map<String, dynamic> row) =>
      MarketingFlowService.isUnreadNotificationRow(row);

  int _mainInboxCount() =>
      _items.where(MarketingFlowService.isVisibleInMainInbox).length;

  int _unreadCountForTab(int tabIndex) {
    return _items.where((n) {
      if (!_isUnread(n)) return false;
      if (MarketingFlowService.isSecurityNoiseNotificationRow(n)) return false;
      if (MarketingFlowService.isChatStyleNotificationRow(n)) return false;
      if (tabIndex == _archiveIndex) {
        return MarketingFlowService.isArchivedNotificationRow(n);
      }
      if (MarketingFlowService.isArchivedNotificationRow(n)) return false;
      if (tabIndex == 0) return true;
      return _categoryForRow(n) == tabIndex;
    }).length;
  }

  String _bodyForRow(Map<String, dynamic> row) {
    final data = _dataMap(row);
    if (_isAr) {
      final b = (data['body_ar'] ??
              data['body'] ??
              row['body'] ??
              row['message'] ??
              '')
          .toString()
          .trim();
      if (b.isNotEmpty) {
        return AppBranding.normalizeUserFacing(b, isAr: true);
      }
    } else {
      final b = (data['body_en'] ??
              data['body'] ??
              row['body'] ??
              row['message'] ??
              '')
          .toString()
          .trim();
      if (b.isNotEmpty) {
        return AppBranding.normalizeUserFacing(b, isAr: false);
      }
    }
    return AppBranding.normalizeUserFacing(
      (row['body'] ?? row['message'] ?? '').toString(),
      isAr: _isAr,
    );
  }

  void _removeLocalById(String id) {
    if (id.isEmpty) return;
    setState(() {
      _items = _items
          .where((e) => (e['id']?.toString() ?? '') != id)
          .toList();
    });
  }

  void _markLocalRead(String id) {
    if (id.isEmpty) return;
    setState(() {
      _items = [
        for (final e in _items)
          if ((e['id']?.toString() ?? '') == id)
            {...e, 'is_read': true}
          else
            e,
      ];
    });
  }

  /// شاشة لمسيّة ضيقة: السحب إضافي — الأزرار تظهر دائماً.
  bool get _isCompactTouch => ViewportScrollPolicy.isCompactTouchLike(context);

  Future<void> _runDelete(String id) async {
    if (id.isEmpty) return;
    try {
      await _svc.deleteInAppNotification(id);
    } catch (_) {}
    if (!mounted) return;
    _removeLocalById(id);
    InAppNotificationHub.onInboxInvalidate?.call();
  }

  Future<void> _runArchive(String id) async {
    if (id.isEmpty) return;
    try {
      await _svc.archiveInAppNotification(id);
    } catch (_) {}
    if (!mounted) return;
    _removeLocalById(id);
    InAppNotificationHub.onInboxInvalidate?.call();
  }

  Future<void> _runBulkArchive() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    if (_tabCtrl.index == _archiveIndex) {
      for (final id in ids) {
        try {
          await _svc.unarchiveInAppNotification(id);
        } catch (_) {}
      }
    } else {
      await CommunicationHubService.archiveNotificationsBulk(
        Supabase.instance.client,
        ids,
      );
    }
    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
      _selectMode = false;
    });
    for (final id in ids) {
      _removeLocalById(id);
    }
    await _load();
  }

  Future<void> _runBulkDelete() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    await CommunicationHubService.deleteNotificationsBulk(
      Supabase.instance.client,
      ids,
    );
    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
      _selectMode = false;
    });
    for (final id in ids) {
      _removeLocalById(id);
    }
    InAppNotificationHub.onInboxInvalidate?.call();
    await _load();
  }

  Widget _adTile(AdItem ad, AppLocalizations l10n) {
    final title = ad.title(_lang);
    final sub = ad.subtitle(_lang);
    final cover = ad.bestCoverUrl();
    return ListTile(
      leading: cover != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                cover,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.campaign_outlined),
              ),
            )
          : const Icon(Icons.campaign_outlined),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: sub.trim().isEmpty ? null : Text(sub),
      trailing: const Icon(Icons.open_in_new_rounded),
      onTap: () {
        final u = (ad.linkUrl ?? '').trim();
        if (u.isEmpty) return;
        final uri = Uri.tryParse(u);
        if (uri != null) {
          unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
        }
      },
    );
  }

  Widget _buildTile(Map<String, dynamic> n, AppLocalizations l10n) {
    final id = (n['id'] ?? '').toString();
    final type = (n['type'] ?? '').toString();
    final dataMap = _dataMap(n);
    final ent = (n['entity_type'] ?? dataMap['entity_type'] ?? '')
        .toString();
    final title = _titleForRow(n);
    final body = _bodyForRow(n);
    final accent = InAppNotificationHub.accentForType(
      type,
      entityType: ent,
    );
    final icon = InAppNotificationHub.iconForType(
      type,
      entityType: ent,
    );
    final cs = Theme.of(context).colorScheme;
    const showInlineActions = true;

    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: _selectMode
          ? Icon(
              _selectedIds.contains(id)
                  ? Icons.check_circle
                  : Icons.circle_outlined,
              color: _selectedIds.contains(id) ? cs.primary : cs.outline,
            )
          : Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          if (_isUnread(n))
            PositionedDirectional(
              top: -2,
              start: -2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cs.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        title.isEmpty ? l10n.notificationDefaultTitle : title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (body.trim().isNotEmpty) Text(body),
            if ((dataMap['media_url'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _mediaThumb((dataMap['media_url'] ?? '').toString().trim()),
            ],
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showInlineActions) ...[
            IconButton(
              tooltip: _isAr ? 'أرشفة' : 'Archive',
              onPressed: () => _runArchive(id),
              icon: Icon(
                Icons.archive_outlined,
                color: cs.outline,
              ),
            ),
            IconButton(
              tooltip: _isAr ? 'حذف' : 'Delete',
              onPressed: () => _runDelete(id),
              icon: Icon(
                Icons.delete_outline,
                color: cs.outline,
              ),
            ),
          ],
          Icon(
            Icons.chevron_right_rounded,
            color: cs.outline,
          ),
        ],
      ),
      onTap: () async {
        if (_selectMode) {
          setState(() {
            if (_selectedIds.contains(id)) {
              _selectedIds.remove(id);
            } else {
              _selectedIds.add(id);
            }
          });
          return;
        }
        _markLocalRead(id);
        try {
          await _svc.markNotificationRead(id);
        } catch (_) {}
        widget.onInboxSurfaceChanged?.call();
        InAppNotificationHub.onInboxInvalidate?.call();
        if (!mounted) return;
        await InAppNotificationRouter.open(
          context,
          n,
          lang: _lang,
          markAsRead: true,
        );
        if (mounted) await _load();
      },
    );

    // على الشاشات الكبيرة/سطح المكتب: نُبقي الإجراءات الصريحة وأي Dismissible
    // قد يلتقط حركات الـ trackpad بطريقة مزعجة، لذا لا نُغلِّف بـ Slidable.
    if (!_isCompactTouch) {
      return tile;
    }

    // على الجوّال/متصفّح الجوّال: نُمكِّن السحب يميناً لإظهار «أرشفة + حذف».
    return SwipeActionsTile(
      key: ValueKey<String>('inapp_swipe_$id'),
      actions: [
        SwipeAction(
          icon: Icons.archive_outlined,
          label: _isAr ? 'أرشفة' : 'Archive',
          color: cs.tertiary,
          onPressed: () => _runArchive(id),
        ),
        SwipeAction(
          icon: Icons.delete_outline,
          label: _isAr ? 'حذف' : 'Delete',
          color: cs.error,
          onPressed: () => _runDelete(id),
        ),
      ],
      child: tile,
    );
  }

  List<Map<String, dynamic>> _filteredInbox(List<Map<String, dynamic>> rows) {
    final q = normalizeForListSearch(_inboxSearch.text);
    if (q.isEmpty) return rows;
    return rows.where((n) {
      final title = normalizeForListSearch(_titleForRow(n));
      final body = normalizeForListSearch(_bodyForRow(n));
      final type = normalizeForListSearch((n['type'] ?? '').toString());
      return title.contains(q) || body.contains(q) || type.contains(q);
    }).toList();
  }

  List<InboxFilterTab> _filterTabs() {
    final labels = widget.campaignsOnly
        ? (_isAr ? const ['الكل', 'الأرشيف'] : const ['All', 'Archive'])
        : (_isAr
            ? const ['الكل', 'التسويق', 'أخرى', 'الأرشيف']
            : const ['All', 'Listings', 'Other', 'Archive']);
    return List.generate(labels.length, (i) {
      return InboxFilterTab(
        label: labels[i],
        selected: _tabCtrl.index == i,
        badge: i != _archiveIndex ? _unreadCountForTab(i) : 0,
        onTap: () {
          if (_tabCtrl.index == i) return;
          _tabCtrl.animateTo(i);
          setState(() {});
        },
      );
    });
  }

  Future<void> _markAllNotificationsRead() async {
    setState(() {
      _items = [
        for (final e in _items) {...e, 'is_read': true},
      ];
    });
    widget.onInboxSurfaceChanged?.call();
    InAppNotificationHub.onInboxInvalidate?.call();
    await CommunicationHubService.markAllNotificationsRead(
      Supabase.instance.client,
    );
    widget.onInboxSurfaceChanged?.call();
    InAppNotificationHub.onInboxInvalidate?.call();
    if (mounted) await _load();
  }

  Future<void> _runBulkMarkRead() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    setState(() {
      _items = [
        for (final e in _items)
          if (ids.contains((e['id'] ?? '').toString()))
            {...e, 'is_read': true}
          else
            e,
      ];
      _selectedIds.clear();
      _selectMode = false;
    });
    widget.onInboxSurfaceChanged?.call();
    InAppNotificationHub.onInboxInvalidate?.call();
    await CommunicationHubService.markNotificationsReadBulk(
      Supabase.instance.client,
      ids,
    );
    widget.onInboxSurfaceChanged?.call();
    InAppNotificationHub.onInboxInvalidate?.call();
    if (mounted) await _load();
  }

  void _onOverflow(String value) {
    switch (value) {
      case 'mark_all':
        unawaited(_markAllNotificationsRead());
        break;
      case 'select':
        setState(() {
          _selectMode = !_selectMode;
          if (!_selectMode) _selectedIds.clear();
        });
        break;
      case 'refresh':
        unawaited(_load());
        break;
      case 'sort':
        setState(() {
          _sort = _sort == _NotifSort.recent
              ? _NotifSort.unreadFirst
              : _NotifSort.recent;
        });
        break;
    }
  }

  Widget _surfaceHeader(AppLocalizations l10n) {
    final visible = _filteredInbox(_visibleItems());
    final hasItems = !_loading && _items.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_searchOpen)
          InboxSearchBar(
            controller: _inboxSearch,
            hintText: l10n.inboxSearchHint,
            onChanged: (_) => setState(() {}),
            onClose: () {
              setState(() {
                _searchOpen = false;
                _inboxSearch.clear();
              });
            },
            closeTooltip: _isAr ? 'إغلاق البحث' : 'Close search',
            fieldBuilder: ({
              required controller,
              required hintText,
              required onChanged,
            }) {
              return AqarTextField(
                controller: controller,
                autofocus: true,
                localeScript: localeScriptFromLang(_lang),
                decoration: InputDecoration(
                  hintText: hintText,
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: onChanged,
              );
            },
          ),
        InboxSurfaceChrome(
          filters: _filterTabs(),
          searchOpen: _searchOpen,
          searchTooltip: _isAr ? 'بحث' : 'Search',
          onToggleSearch: () {
            setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) _inboxSearch.clear();
            });
          },
          overflowTooltip: _isAr ? 'المزيد' : 'More',
          overflowActions: [
            if (hasItems)
              InboxOverflowAction(
                value: 'mark_all',
                icon: Icons.mark_email_read_outlined,
                label: _isAr ? 'قراءة الكل' : 'Mark all read',
              ),
            if (hasItems)
              InboxOverflowAction(
                value: 'select',
                icon: _selectMode
                    ? Icons.close_rounded
                    : Icons.checklist_rounded,
                label: _selectMode
                    ? (_isAr ? 'إنهاء التحديد' : 'Done')
                    : (_isAr ? 'تحديد' : 'Select'),
              ),
            InboxOverflowAction(
              value: 'sort',
              icon: Icons.sort_rounded,
              label: _sort == _NotifSort.unreadFirst
                  ? (_isAr ? 'الأحدث أولاً' : 'Most recent')
                  : (_isAr ? 'غير المقروء أولاً' : 'Unread first'),
            ),
            InboxOverflowAction(
              value: 'refresh',
              icon: Icons.refresh_rounded,
              label: _isAr ? 'تحديث' : 'Refresh',
            ),
          ],
          onOverflowSelected: _onOverflow,
        ),
        if (_selectMode)
          InboxBulkToolbar(
            isAr: _isAr,
            selectedCount: _selectedIds.length,
            totalCount: visible.length,
            onSelectAll: () {
              setState(() {
                _selectedIds
                  ..clear()
                  ..addAll(
                    visible
                        .map((e) => (e['id'] ?? '').toString())
                        .where((s) => s.isNotEmpty),
                  );
              });
            },
            onClearSelection: () => setState(() => _selectedIds.clear()),
            onMarkRead: _runBulkMarkRead,
            onArchive: _runBulkArchive,
            onDelete: _runBulkDelete,
            showArchive: true,
          ),
      ],
    );
  }

  Widget _inboxBody(AppLocalizations l10n) {
    final visible = _filteredInbox(_visibleItems());
    if (_loading) {
      return const Center(child: AppLogoLoading());
    }
    if (_err != null) {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: cs.onSurface),
              const SizedBox(height: 12),
              Text(
                _err!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _load,
                child: Text(_isAr ? 'إعادة المحاولة' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final ads = widget.campaignsOnly && _tabCtrl.index == 0 ? _hubAds : const <AdItem>[];
    if (_items.isEmpty && ads.isEmpty) {
      return Center(child: Text(l10n.noNewNotifications));
    }
    final mainCount = _mainInboxCount();
    if (visible.isEmpty && ads.isEmpty && mainCount > 0 && _tabCtrl.index != _archiveIndex) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isAr
                    ? 'لا توجد إشعارات في هذا التصفية — جرّب «الكل» أو «الأرشيف».'
                    : 'No notifications in this filter — try All or Archive.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  _tabCtrl.animateTo(0);
                  _inboxSearch.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.inbox_outlined),
                label: Text(_isAr ? 'عرض الكل ($mainCount)' : 'Show all ($mainCount)'),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: visible.isEmpty && ads.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _isAr
                          ? 'لا توجد إشعارات في هذا التبويب.'
                          : 'No notifications in this tab.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: ads.length + visible.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      if (i < ads.length) {
                        return _adTile(ads[i], l10n);
                      }
                      return _buildTile(visible[i - ads.length], l10n);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (widget.embedMode) {
      return Directionality(
        textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _surfaceHeader(l10n),
            Expanded(child: _inboxBody(l10n)),
          ],
        ),
      );
    }

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: Navigator.canPop(context)
              ? AppPageCloseButton(
                  isArabic: _isAr,
                )
              : null,
          title: Text(l10n.notificationsTitle),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _surfaceHeader(l10n),
            Expanded(child: _inboxBody(l10n)),
          ],
        ),
      ),
    );
  }
}
