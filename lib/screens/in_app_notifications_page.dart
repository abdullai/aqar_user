// lib/screens/in_app_notifications_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/search_normalize.dart';
import '../core/notifications/in_app_notification_catalog.dart';
import '../l10n/app_localizations.dart';
import '../services/in_app_notification_hub.dart';
import '../services/in_app_notification_router.dart';
import '../services/marketing_flow_service.dart';
import '../services/notification_service.dart';
import '../widgets/app_logo_loading.dart';

class InAppNotificationsPage extends StatefulWidget {
  final String lang;

  /// بدون [Scaffold]/[AppBar] — للتضمين داخل مركز الإشعارات والمحادثات.
  final bool embedMode;

  const InAppNotificationsPage({
    super.key,
    required this.lang,
    this.embedMode = false,
  });

  @override
  State<InAppNotificationsPage> createState() => _InAppNotificationsPageState();
}

class _InAppNotificationsPageState extends State<InAppNotificationsPage>
    with SingleTickerProviderStateMixin {
  final _svc = MarketingFlowService(Supabase.instance.client);
  late final TabController _tabCtrl;
  final _inboxSearch = TextEditingController();

  bool _loading = true;
  String? _err;
  List<Map<String, dynamic>> _items = const [];

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
    _tabCtrl = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await MarketingFlowService(Supabase.instance.client)
            .markAllInAppNotificationsRead();
      } catch (_) {}
      await NotificationService.clearOsApplicationIconBadge();
      InAppNotificationHub.onInboxInvalidate?.call();
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
      final rows = await _svc.myInAppNotificationsInbox();
      setState(() => _items = rows);
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
    if (i == 0) return List<Map<String, dynamic>>.from(_items);
    return _items
        .where((n) => _categoryForRow(n) == i)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  String _titleForRow(Map<String, dynamic> row) {
    final data = _dataMap(row);
    if (_isAr) {
      final t = (data['title_ar'] ?? data['title'] ?? row['title'] ?? '')
          .toString()
          .trim();
      if (t.isNotEmpty) return t;
    } else {
      final t = (data['title_en'] ?? data['title'] ?? row['title'] ?? '')
          .toString()
          .trim();
      if (t.isNotEmpty) return t;
    }
    return (row['title'] ?? row['type'] ?? '').toString();
  }

  int _unreadCountForTab(int tabIndex) {
    return _items.where((n) {
      if (!_isUnread(n)) return false;
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

  bool _isUnread(Map<String, dynamic> row) {
    final v = row['is_read'];
    if (v == null) return true;
    if (v is bool) return !v;
    final s = v.toString().toLowerCase();
    return s != 'true' && s != '1';
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
      if (b.isNotEmpty) return b;
    } else {
      final b = (data['body_en'] ??
              data['body'] ??
              row['body'] ??
              row['message'] ??
              '')
          .toString()
          .trim();
      if (b.isNotEmpty) return b;
    }
    return (row['body'] ?? row['message'] ?? '').toString();
  }

  void _removeLocalById(String id) {
    if (id.isEmpty) return;
    setState(() {
      _items = _items
          .where((e) => (e['id']?.toString() ?? '') != id)
          .toList();
    });
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

    return Dismissible(
      key: ValueKey<String>('inapp_$id'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async => true,
      onDismissed: (_) async {
        if (id.isEmpty) return;
        try {
          await _svc.deleteInAppNotification(id);
        } catch (_) {}
        if (!mounted) return;
        _removeLocalById(id);
        InAppNotificationHub.onInboxInvalidate?.call();
      },
      background: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onError,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Stack(
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
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
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
            IconButton(
              tooltip: _isAr ? 'حذف' : 'Delete',
              onPressed: () async {
                if (id.isEmpty) return;
                try {
                  await _svc.deleteInAppNotification(id);
                } catch (_) {}
                if (!mounted) return;
                InAppNotificationHub.onInboxInvalidate?.call();
                await _load();
              },
              icon: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.outline,
            ),
          ],
        ),
        onTap: () async {
          await InAppNotificationRouter.open(
            context,
            n,
            lang: _lang,
            markAsRead: true,
          );
          if (mounted) await _load();
        },
      ),
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

  PreferredSizeWidget _filterTabBar(AppLocalizations l10n) {
    return TabBar(
      controller: _tabCtrl,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [
        _tabWithBadge(_isAr ? 'الكل' : 'All', 0),
        _tabWithBadge(_isAr ? 'التسويق' : 'Listings', 1),
        _tabWithBadge(_isAr ? 'دردشة' : 'Chat', 2),
        _tabWithBadge(_isAr ? 'أخرى' : 'Other', 3),
      ],
    );
  }

  List<Widget> _inboxToolbarActions() {
    return [
      if (!_loading && _items.isNotEmpty)
        TextButton(
          onPressed: () async {
            await _svc.markAllInAppNotificationsRead();
            if (mounted) await _load();
          },
          child: Text(
            _isAr ? 'الكل مقروء' : 'Mark all read',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            child: TextField(
              controller: _inboxSearch,
              decoration: InputDecoration(
                hintText: l10n.inboxSearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                border: const OutlineInputBorder(),
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
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(
                controller: _tabCtrl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  _tabWithBadge(_isAr ? 'الكل' : 'All', 0),
                  _tabWithBadge(_isAr ? 'التسويق' : 'Listings', 1),
                  _tabWithBadge(_isAr ? 'دردشة' : 'Chat', 2),
                  _tabWithBadge(_isAr ? 'أخرى' : 'Other', 3),
                ],
              ),
            ),
            if (!_loading && _items.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 0),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  children: _inboxToolbarActions(),
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
