// lib/screens/in_app_notifications_page.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/app_branding.dart';
import '../core/utils/search_normalize.dart';
import '../core/notifications/in_app_notification_catalog.dart';
import '../core/input/locale_text_input_guard.dart';
import '../l10n/app_localizations.dart';
import '../services/communication_hub_service.dart';
import '../services/in_app_notification_hub.dart';
import '../services/in_app_notification_router.dart';
import '../services/marketing_flow_service.dart';
import '../services/notification_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/inbox_bulk_toolbar.dart';
import '../widgets/stable_select_chip.dart';
import '../widgets/swipe_actions_tile.dart';

class InAppNotificationsPage extends StatefulWidget {
  final String lang;

  /// بدون [Scaffold]/[AppBar] — للتضمين داخل مركز الإشعارات والمحادثات.
  final bool embedMode;

  /// يُستدعى بعد تحديث قائمة الصندوق (مثلاً لتحديث شارة تبويب «الإشعارات» في [CommunicationHubPage]).
  final VoidCallback? onInboxSurfaceChanged;

  const InAppNotificationsPage({
    super.key,
    required this.lang,
    this.embedMode = false,
    this.onInboxSurfaceChanged,
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
  bool _selectMode = false;
  final Set<String> _selectedIds = {};
  _NotifSort _sort = _NotifSort.recent;

  String get _lang {
    final fromRoute =
        (ModalRoute.of(context)?.settings.arguments as Map?)?['lang'];
    if (fromRoute is String && fromRoute.trim().isNotEmpty) {
      return fromRoute.trim().toLowerCase() == 'en' ? 'en' : 'ar';
    }
    return widget.lang.toLowerCase() == 'en' ? 'en' : 'ar';
  }

  bool get _isAr => _lang != 'en';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this, initialIndex: 0)
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
      setState(() => _items = rows);
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (mounted) {
      widget.onInboxSurfaceChanged?.call();
      InAppNotificationHub.onInboxInvalidate?.call();
    }
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

  /// 0=الكل، 1=تسويق/عقود، 2=دردشة، 3=أخرى
  int _categoryForRow(Map<String, dynamic> n) {
    final type = (n['type'] ?? '').toString().toLowerCase().trim();
    final data = _dataMap(n);
    final ent = (n['entity_type'] ?? data['entity_type'] ?? '')
        .toString()
        .toLowerCase()
        .trim();

    if (type == InAppNotifTypes.chatMessage ||
        type == 'message' ||
        type == 'chat') {
      return 2;
    }

    if (_isMarketingOrListingType(type, ent)) return 1;

    return 3;
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
    if (i == 4) {
      base = _items.where(MarketingFlowService.isArchivedNotificationRow);
    } else {
      base = _items.where(MarketingFlowService.isVisibleInMainInbox);
      if (i != 0) {
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
    if (_isAr) {
      final t = (data['title_ar'] ?? data['title'] ?? row['title'] ?? '')
          .toString()
          .trim();
      if (t.isNotEmpty) {
        return AppBranding.normalizeUserFacing(t, isAr: true);
      }
    } else {
      final t = (data['title_en'] ?? data['title'] ?? row['title'] ?? '')
          .toString()
          .trim();
      if (t.isNotEmpty) {
        return AppBranding.normalizeUserFacing(t, isAr: false);
      }
    }
    return AppBranding.normalizeUserFacing(
      (row['title'] ?? row['type'] ?? '').toString(),
      isAr: _isAr,
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
      if (tabIndex == 4) {
        return MarketingFlowService.isArchivedNotificationRow(n);
      }
      if (MarketingFlowService.isArchivedNotificationRow(n)) return false;
      if (tabIndex == 0) return true;
      return _categoryForRow(n) == tabIndex;
    }).length;
  }

  Widget _tabWithBadge(String title, int tabIndex) {
    final n = _unreadCountForTab(tabIndex);
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title),
          if (n > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$n',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  height: 1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
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

  /// شاشة تمثَّل بأنها «لمسيّة»: تطبيق الجوّال أو متصفّح ضيّق.
  bool get _isTouchScreen {
    if (!kIsWeb) return true;
    final w = MediaQuery.sizeOf(context).width;
    return w < 800;
  }

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
    if (_tabCtrl.index == 4) {
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
    final showInlineActions = !_isTouchScreen;

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
      subtitle: body.trim().isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(body),
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
    if (showInlineActions) {
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

  Widget _embedFilterChips() {
    final labels = _isAr
        ? const ['الكل', 'التسويق', 'مراسلة', 'أخرى', 'الأرشيف']
        : const ['All', 'Listings', 'Messaging', 'Other', 'Archive'];
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 4),
        child: Row(
          children: List.generate(labels.length, (i) {
            final selected = _tabCtrl.index == i;
            final badge = i < 4 ? _unreadCountForTab(i) : 0;
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: StableSelectChip(
                exclusive: true,
                label: badge > 0 ? '${labels[i]} ($badge)' : labels[i],
                selected: selected,
                onSelected: (_) {
                  if (_tabCtrl.index == i) return;
                  _tabCtrl.animateTo(i);
                  setState(() {});
                },
              ),
            );
          }),
        ),
      ),
    );
  }
  PreferredSizeWidget _filterTabBar(AppLocalizations l10n) {
    return TabBar(
      controller: _tabCtrl,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [
        _tabWithBadge(_isAr ? 'الكل' : 'All', 0),
        _tabWithBadge(_isAr ? 'التسويق' : 'Listings', 1),
        _tabWithBadge(_isAr ? 'مراسلة' : 'Messaging', 2),
        _tabWithBadge(_isAr ? 'أخرى' : 'Other', 3),
        Tab(text: _isAr ? 'الأرشيف' : 'Archive'),
      ],
    );
  }

  List<Widget> _inboxToolbarActions() {
    return [
      if (!_loading && _items.isNotEmpty)
        TextButton(
          onPressed: () async {
            await CommunicationHubService.markEverythingRead(
              Supabase.instance.client,
            );
            if (mounted) await _load();
          },
          child: Text(
            _isAr ? 'قراءة الكل' : 'Mark all read',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      if (!_loading && _items.isNotEmpty)
        TextButton(
          onPressed: () {
            setState(() {
              _selectMode = !_selectMode;
              if (!_selectMode) _selectedIds.clear();
            });
          },
          child: Text(
            _selectMode ? (_isAr ? 'إنهاء' : 'Done') : (_isAr ? 'تحديد' : 'Select'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      if (!_loading && _items.isNotEmpty)
        IconButton(
          tooltip: _isAr ? 'تحديث' : 'Refresh',
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
    ];
  }

  Widget _inboxBody(AppLocalizations l10n) {
    final visible = _filteredInbox(_visibleItems());
    if (_loading) {
      return const Center(child: AppLogoLoading());
    }
    if (_err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_err!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(child: Text(l10n.noNewNotifications));
    }
    final mainCount = _mainInboxCount();
    if (visible.isEmpty && mainCount > 0 && _tabCtrl.index != 4) {
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
                    visible.map((e) => (e['id'] ?? '').toString()).where((s) => s.isNotEmpty),
                  );
              });
            },
            onClearSelection: () => setState(() => _selectedIds.clear()),
            onArchive: _runBulkArchive,
            onDelete: _runBulkDelete,
            showArchive: true,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            _isAr
                ? 'إشعارات العمليات والتسويق هنا. رموز التحقق (OTP) لا تُعرض في هذه القائمة. استخدم التبويبات للتصفية.'
                : 'Workflow notifications appear here. OTP codes are hidden. Use tabs to filter.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (_items.length > 6)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: AqarTextField(
              controller: _inboxSearch,
              localeScript: localeScriptFromLang(_lang),
              decoration: InputDecoration(
                hintText: l10n.inboxSearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        Expanded(
          child: visible.isEmpty
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
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      return _buildTile(visible[i], l10n);
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
            _embedFilterChips(),
            if (!_loading && _items.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: _isAr,
                  child: Row(
                    children: _inboxToolbarActions(),
                  ),
                ),
              ),
            Expanded(child: _inboxBody(l10n)),
          ],
        ),
      );
    }

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.notificationsTitle),
          bottom: _filterTabBar(l10n),
          actions: _inboxToolbarActions(),
        ),
        body: _inboxBody(l10n),
      ),
    );
  }
}
