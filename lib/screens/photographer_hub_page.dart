import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aqar_user/core/gestures/app_keyboard_popups.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/subscription/marketing_subscription_resume_intent.dart';
import '../core/utils/app_money.dart';
import '../core/utils/date_helper.dart';
import '../core/utils/rpc_user_message.dart';
import '../l10n/app_localizations.dart';
import '../services/photographer_service.dart';
import '../services/in_app_notification_hub.dart';
import '../services/subscription_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/aqar_text_field.dart';
import '../widgets/certified_photographer_name.dart';
import 'subscriptions/subscriptions_root_screen.dart';
import 'photographer_deliver_page.dart';
import 'photographer_join_page.dart';

class PhotographerHubPage extends StatefulWidget {
  const PhotographerHubPage({
    super.key,
    required this.lang,
    this.embedAppBar = false,
    this.initialTab = 0,
    this.matchesMyPageFilters,
  });
  static final ValueNotifier<Map<String, dynamic>?> pendingDeepLink =
      ValueNotifier<Map<String, dynamic>?>(null);
  static final ValueNotifier<int> refreshRevision = ValueNotifier<int>(0);

  static void openDeepLink(Map<String, dynamic> data) {
    pendingDeepLink.value = Map<String, dynamic>.from(data);
  }

  static void refreshCurrentPage() {
    refreshRevision.value++;
  }

  final String lang;
  final bool embedAppBar;
  final int initialTab;
  final bool Function(Map<String, dynamic>)? matchesMyPageFilters;

  @override
  State<PhotographerHubPage> createState() => _PhotographerHubPageState();
}

class _PhotographerHubPageState extends State<PhotographerHubPage>
    with TickerProviderStateMixin {
  final _svc = PhotographerService(Supabase.instance.client);
  late final TabController _roleTabs;
  late final TabController _requesterTabs;
  late final TabController _tabs;
  final Map<String, GlobalKey> _deepLinkCardKeys = {};
  String? _deepLinkTarget;
  String? _deepLinkFallbackTarget;
  PhotographerProfile? _profile;
  List<PhotoShootRequest> _shots = const [];
  List<PhotoShootRequest> _requesterShots = const [];
  List<Map<String, dynamic>> _opportunities = const [];
  List<Map<String, dynamic>> _myOffers = const [];
  List<Map<String, dynamic>> _incomingOffers = const [];
  var _loading = true;
  var _providerLoading = false;
  var _subscriptionRequired = false;
  RealtimeChannel? _shootsRealtimeChannel;
  RealtimeChannel? _requesterRealtimeChannel;
  RealtimeChannel? _propertyOwnerRealtimeChannel;
  RealtimeChannel? _offersRealtimeChannel;
  StreamSubscription<Map<String, dynamic>>? _subscriptionEvents;
  DateTime _calDay = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  Timer? _tick;

  bool get _isAr => widget.lang != 'en';

  @override
  void initState() {
    super.initState();
    _roleTabs = TabController(length: 2, vsync: this);
    _requesterTabs = TabController(length: 3, vsync: this);
    _tabs = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _subscribeRealtime();
    PhotographerHubPage.pendingDeepLink.addListener(_onPendingDeepLink);
    PhotographerHubPage.refreshRevision.addListener(_onRefreshRequested);
    InAppNotificationHub.inboxRevision.addListener(_onInboxRevision);
    if (PhotographerHubPage.pendingDeepLink.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onPendingDeepLink());
    }
    _reload();
  }

  GlobalKey _deepLinkCardKey(String id) =>
      _deepLinkCardKeys.putIfAbsent(id, GlobalKey.new);

  bool _matchesMyPageFilters(Map<String, dynamic> row) =>
      widget.matchesMyPageFilters?.call(row) ?? true;

  Map<String, dynamic> _shootSearchRow(PhotoShootRequest shoot) => {
        'id': shoot.id,
        'request_id': shoot.id,
        'title': shoot.listingTitle,
        'city': shoot.listingCity,
        'listing_request_public_code': shoot.listingPublicCode,
        'purpose': shoot.listingPurpose,
        'price': shoot.listingPrice,
        'quoted_amount_sar': shoot.quotedAmountSar,
        'shoot_kinds': shoot.shootKinds,
        'location_text': shoot.locationText,
        'status': shoot.status,
      };

  List<PhotoShootRequest> _filteredShoots(
    Iterable<PhotoShootRequest> shoots,
  ) =>
      shoots
          .where((shoot) => _matchesMyPageFilters(_shootSearchRow(shoot)))
          .toList();

  Map<String, dynamic> _offerSearchRow(Map<String, dynamic> offer) {
    final requestId = (offer['request_id'] ?? '').toString();
    final request = _requesterShots.cast<PhotoShootRequest?>().firstWhere(
          (shoot) => shoot?.id == requestId,
          orElse: () => null,
        );
    final preview = offer['listing_preview'] is Map
        ? Map<String, dynamic>.from(offer['listing_preview'] as Map)
        : const <String, dynamic>{};
    return {
      ...preview,
      if (request != null) ..._shootSearchRow(request),
      'id': requestId,
      'request_id': requestId,
      'offer_id': offer['offer_id'],
      'details': offer['details'],
      'amount_sar': offer['amount_sar'],
      'display_name': offer['display_name'],
    };
  }

  void _onInboxRevision() {
    if (mounted) unawaited(_reload(silent: true));
  }

  void _onRefreshRequested() {
    if (mounted) unawaited(_reload());
  }

  void _onPendingDeepLink() {
    final data = PhotographerHubPage.pendingDeepLink.value;
    if (data == null) return;
    PhotographerHubPage.pendingDeepLink.value = null;
    final mode = (data['photographer_mode'] ?? data['role'] ?? '').toString();
    final requesterMode = mode == 'requester' || mode == 'owner';
    final tab = int.tryParse('${data['photographer_tab'] ?? ''}') ?? 0;
    final requestId = (data['shoot_request_id'] ?? '').toString().trim();
    final offerId = (data['photo_shoot_offer_id'] ?? '').toString().trim();
    _deepLinkFallbackTarget = null;
    if (requesterMode) {
      _roleTabs.animateTo(0);
      _requesterTabs.animateTo(tab.clamp(0, 2));
      if (requestId.isNotEmpty) {
        _deepLinkFallbackTarget = tab == 2
            ? 'requester-track:$requestId'
            : 'requester-request:$requestId';
      }
      _deepLinkTarget = offerId.isNotEmpty && tab == 1
          ? 'requester-offer:$offerId'
          : _deepLinkFallbackTarget;
    } else {
      _roleTabs.animateTo(1);
      _tabs.animateTo(tab.clamp(0, 3));
      if (requestId.isNotEmpty) {
        _deepLinkFallbackTarget = tab == 2
            ? 'provider-work:$requestId'
            : 'provider-request:$requestId';
      }
      _deepLinkTarget = offerId.isNotEmpty && tab == 1
          ? 'provider-offer:$offerId'
          : _deepLinkFallbackTarget;
    }
    unawaited(_reload(silent: true));
  }

  Future<void> _focusDeepLinkCard() async {
    final target = _deepLinkTarget;
    if (target == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final ctx = _deepLinkCardKeys[target]?.currentContext;
    final fallback = _deepLinkFallbackTarget == null
        ? null
        : _deepLinkCardKeys[_deepLinkFallbackTarget!]?.currentContext;
    final targetContext = ctx ?? fallback;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 240),
      alignment: 0.18,
    );
  }

  void _subscribeRealtime() {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return;

    SubscriptionService.ensureRealtimeChannelFor(client, uid);
    _subscriptionEvents = SubscriptionService.subscriptionEvents.listen((_) {
      if (mounted) unawaited(_reload(silent: true));
    });
    try {
      final channel = client.channel('photographer_shoots_$uid');
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'photo_shoot_requests',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'photographer_id',
          value: uid,
        ),
        callback: (_) {
          if (mounted) unawaited(_reload(silent: true));
        },
      );
      channel.subscribe();
      _shootsRealtimeChannel = channel;

      final requesterChannel = client.channel('photo_requester_shoots_$uid');
      requesterChannel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'photo_shoot_requests',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'requester_id',
          value: uid,
        ),
        callback: (_) {
          if (mounted) unawaited(_reload(silent: true));
        },
      );
      requesterChannel.subscribe();
      _requesterRealtimeChannel = requesterChannel;

      final propertyOwnerChannel =
          client.channel('photo_property_owner_shoots_$uid');
      propertyOwnerChannel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'photo_shoot_requests',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'property_owner_id',
          value: uid,
        ),
        callback: (_) {
          if (mounted) unawaited(_reload(silent: true));
        },
      );
      propertyOwnerChannel.subscribe();
      _propertyOwnerRealtimeChannel = propertyOwnerChannel;

      final offerChannel = client.channel('photo_shoot_offers_$uid');
      offerChannel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'photo_shoot_offers',
        callback: (_) {
          if (mounted) unawaited(_reload(silent: true));
        },
      );
      offerChannel.subscribe();
      _offersRealtimeChannel = offerChannel;
    } catch (_) {}
  }

  @override
  void dispose() {
    _tick?.cancel();
    PhotographerHubPage.pendingDeepLink.removeListener(_onPendingDeepLink);
    PhotographerHubPage.refreshRevision.removeListener(_onRefreshRequested);
    InAppNotificationHub.inboxRevision.removeListener(_onInboxRevision);
    _subscriptionEvents?.cancel();
    try {
      _shootsRealtimeChannel?.unsubscribe();
      _requesterRealtimeChannel?.unsubscribe();
      _propertyOwnerRealtimeChannel?.unsubscribe();
      _offersRealtimeChannel?.unsubscribe();
    } catch (_) {}
    _tabs.dispose();
    _roleTabs.dispose();
    _requesterTabs.dispose();
    super.dispose();
  }

  Future<void> _reload({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    PhotographerProfile? p;
    List<PhotoShootRequest> requesterShots = const [];
    List<PhotoShootRequest> photographerShots = const [];
    List<Map<String, dynamic>> opportunities = const [];
    List<Map<String, dynamic>> myOffers = const [];
    List<Map<String, dynamic>> incomingOffers = const [];
    var subscriptionRequired = false;
    final requesterData = await Future.wait<Object?>([
      _svc.myProfile().then<Object?>((value) => value).catchError((_) => null),
      _svc
          .myShootsAsRequester()
          .then<Object?>((value) => value)
          .catchError((_) => null),
      _svc
          .myIncomingPhotoShootOffers()
          .then<Object?>((value) => value)
          .catchError((_) => null),
    ]);
    p = requesterData[0] as PhotographerProfile?;
    requesterShots = requesterData[1] as List<PhotoShootRequest>? ?? const [];
    incomingOffers =
        requesterData[2] as List<Map<String, dynamic>>? ?? const [];
    if (!mounted) return;
    setState(() {
      _profile = p;
      _requesterShots = requesterShots;
      _incomingOffers = incomingOffers;
      _loading = false;
      _providerLoading = p?.isVerified == true;
    });
    if (p?.isVerified == true) {
      Map<String, dynamic>? subscription;
      try {
        subscription = await SubscriptionService(Supabase.instance.client)
            .getCurrentSubscriptionForPlanUserType('photographer');
      } catch (_) {}
      subscriptionRequired =
          !SubscriptionService.subscriptionRowInPaidAccess(subscription);
      final providerCoreData = await Future.wait<Object?>([
        _svc
            .myShootsAsPhotographer()
            .then<Object?>((value) => value)
            .catchError((_) => null),
        _svc
            .myPhotoShootOffers()
            .then<Object?>((value) => value)
            .catchError((_) => null),
      ]);
      photographerShots =
          providerCoreData[0] as List<PhotoShootRequest>? ?? const [];
      myOffers = providerCoreData[1] as List<Map<String, dynamic>>? ?? const [];
      if (!subscriptionRequired) {
        try {
          opportunities = await _svc.openPhotoShootOpportunities();
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _providerLoading = false;
      _shots = photographerShots;
      _opportunities = opportunities;
      _myOffers = myOffers;
      _subscriptionRequired = subscriptionRequired;
    });
    if (_deepLinkTarget != null) unawaited(_focusDeepLinkCard());
  }

  Future<void> _openPhotographerPlans() async {
    await Navigator.of(context).push<MarketingSubscriptionResumeIntent?>(
      MaterialPageRoute<MarketingSubscriptionResumeIntent?>(
        builder: (_) => SubscriptionsRootScreen(
          lang: widget.lang,
          accountType: 'photographer',
          embedAppBar: true,
          resumeAfterPurchase: const MarketingSubscriptionResumeIntent(
            kind: MarketingSubscriptionResumeKind.postPaidUnlock,
          ),
        ),
      ),
    );
    if (!mounted) return;
    SubscriptionService.invalidateSubscriptionCache();
    await _reload();
  }

  Widget _subscriptionRequiredPage(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_camera_outlined, size: 44, color: cs.primary),
              const SizedBox(height: 12),
              Text(
                _isAr
                    ? 'افتح فرص تصوير جديدة'
                    : 'Unlock photography opportunities',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _isAr
                    ? 'قدّم عروضك على طلبات تصوير العقارات، وتابع الأعمال المسندة إليك وسلّم الصور والفيديو والجولات بعد اعتماد باقة المصوّر.'
                    : 'Bid on property shoots, manage awarded work, and deliver photos, video, and tours with an active photographer plan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
              ),
              if (_myOffers.isNotEmpty || _shots.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _isAr
                      ? 'محفوظ للمتابعة: ${_myOffers.length} عرض · ${_shots.length} طلب عمل'
                      : 'Saved for tracking: ${_myOffers.length} offers · ${_shots.length} assigned shoots',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _openPhotographerPlans,
                icon: const Icon(Icons.subscriptions_outlined),
                label: Text(
                    _isAr ? 'عرض باقات المصور' : 'View photographer plans'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<PhotoShootRequest> _of(Iterable<String> st) =>
      _shots.where((s) => st.contains(s.status)).toList();

  int get _acceptedToday {
    final n = DateTime.now();
    return _shots.where((s) {
      final a = s.acceptedAt;
      if (a == null) return false;
      final l = a.toLocal();
      return l.year == n.year && l.month == n.month && l.day == n.day;
    }).length;
  }

  String _windowLabel(PhotoShootRequest r, AppLocalizations l10n) {
    final left = r.acceptWindowLeft;
    if (left == null) return '';
    if (left.isNegative) return l10n.photographerAcceptWindowExpired;
    final h = left.inHours;
    final m = left.inMinutes.remainder(60);
    if (h > 0) return l10n.photographerAcceptWindow('${h}h ${m}m');
    return l10n.photographerAcceptWindow('${m}m');
  }

  Future<void> _respond(PhotoShootRequest r, bool accept) async {
    final l10n = AppLocalizations.of(context)!;
    if (r.acceptWindowExpired) {
      await _svc.expireStaleShoots();
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photographerAcceptWindowExpired)),
      );
      return;
    }
    String? reason;
    if (!accept) {
      final ctrl = TextEditingController();
      final ok = await showAppDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.photographerDeclineTitle),
          content: AqarTextField(
            controller: ctrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l10n.photographerDeclineReason,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.photographerDialogCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.photographerDeclineConfirm),
            ),
          ],
        ),
      );
      if (ok != true) return;
      reason = ctrl.text.trim();
    }
    try {
      await _svc.respond(
        requestId: r.id,
        accept: accept,
        rejectReason: reason,
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RpcUserMessage.of(e, isAr: _isAr))),
      );
    }
  }

  Future<void> _deliver(PhotoShootRequest r) async {
    final l10n = AppLocalizations.of(context)!;
    if (r.propertyId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photographerNeedListing)),
      );
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PhotographerDeliverPage(
          request: r,
          lang: widget.lang,
        ),
      ),
    );
    if (ok == true) await _reload();
  }

  Future<void> _editCap() async {
    final l10n = AppLocalizations.of(context)!;
    final ctrl = TextEditingController(
      text: '${_profile?.maxAcceptsPerDay ?? 5}',
    );
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.photographerDailyCapTitle),
        content: AqarTextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.photographerDialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.photographerDialogSave),
          ),
        ],
      ),
    );
    final n = int.tryParse(ctrl.text.trim());
    if (ok != true || n == null) return;
    try {
      await _svc.setDailyCap(n);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RpcUserMessage.of(e, isAr: _isAr))),
      );
    }
  }

  String _shootStatusLabel(String status) {
    return switch (status) {
      'open' =>
        _isAr ? 'بانتظار عروض المصورين' : 'Awaiting photographer offers',
      'pending' =>
        _isAr ? 'بانتظار رد المصوّر' : 'Awaiting photographer response',
      'accepted' => _isAr ? 'اختير المصوّر' : 'Photographer selected',
      'in_progress' => _isAr ? 'قيد التنفيذ' : 'In progress',
      'delivered' => _isAr ? 'تم التسليم' : 'Delivered',
      'rejected' => _isAr ? 'مرفوض' : 'Declined',
      'cancelled' => _isAr ? 'ملغي' : 'Cancelled',
      _ => status,
    };
  }

  Widget _requesterRequestCard(PhotoShootRequest request) {
    final offers = _incomingOffers
        .where((offer) => offer['request_id']?.toString() == request.id)
        .where((offer) => offer['offer_status'] == 'submitted')
        .length;
    return Card(
      key: _deepLinkCardKey('requester-request:${request.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              request.listingTitle.trim().isNotEmpty
                  ? request.listingTitle
                  : request.locationText.trim().isEmpty
                      ? AppLocalizations.of(context)!.photographerShootFallback
                      : request.locationText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (request.listingCity.trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(request.listingCity,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
            if (request.listingPublicCode.trim().isNotEmpty)
              Text(
                '${_isAr ? 'رقم الإعلان' : 'Listing'}: ${request.listingPublicCode}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 5),
            Text(request.shootKinds.join(' · ')),
            const SizedBox(height: 5),
            Text(_shootStatusLabel(request.status)),
            if (offers > 0) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _requesterTabs.animateTo(1),
                icon: const Icon(Icons.local_offer_outlined),
                label: Text(
                  _isAr
                      ? 'العروض الواردة ($offers)'
                      : 'Offers received ($offers)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _requesterRequestsPane() {
    final requests = _filteredShoots(_requesterShots);
    if (_loading && _requesterShots.isEmpty) {
      return const Center(child: AppLogoLoading());
    }
    if (requests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _requesterShots.isEmpty
                ? (_isAr
                    ? 'لا توجد طلبات تصوير لعقاراتك حتى الآن.'
                    : 'You have not requested property photography yet.')
                : (_isAr
                    ? 'لا توجد طلبات مطابقة لخيارات البحث.'
                    : 'No requests match these filters.'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) => _requesterRequestCard(requests[index]),
    );
  }

  Future<void> _respondToIncomingOffer(
    Map<String, dynamic> offer,
    bool accept,
  ) async {
    final offerId = (offer['offer_id'] ?? '').toString();
    if (offerId.isEmpty) return;
    try {
      await _svc.respondToPhotoShootOffer(offerId: offerId, accept: accept);
      await _reload(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept
              ? (_isAr ? 'تم اختيار عرض المصوّر.' : 'Photographer selected.')
              : (_isAr ? 'تم رفض العرض.' : 'Offer declined.')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RpcUserMessage.of(e, isAr: _isAr))),
      );
    }
  }

  Widget _incomingOffersPane() {
    final offers = _incomingOffers
        .where((offer) => _matchesMyPageFilters(_offerSearchRow(offer)))
        .toList();
    if (offers.isEmpty) {
      return Center(
        child: Text(_incomingOffers.isEmpty
            ? (_isAr ? 'لا توجد عروض واردة.' : 'No incoming offers.')
            : (_isAr
                ? 'لا توجد عروض مطابقة لخيارات البحث.'
                : 'No offers match these filters.')),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: offers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final offer = offers[index];
        final requestId = (offer['request_id'] ?? '').toString();
        final request = _requesterShots.cast<PhotoShootRequest?>().firstWhere(
              (item) => item?.id == requestId,
              orElse: () => null,
            );
        final status = (offer['offer_status'] ?? '').toString();
        final actionable = status == 'submitted' && request?.status == 'open';
        final name = (offer['display_name'] ?? '').toString().trim();
        final amount = (offer['amount_sar'] as num?)?.toDouble();
        return Card(
          key: _deepLinkCardKey('requester-offer:${offer['offer_id']}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  name.isEmpty
                      ? (_isAr ? 'مصوّر عقاري' : 'Property photographer')
                      : name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                if (request != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    request.listingTitle.trim().isNotEmpty
                        ? request.listingTitle
                        : request.locationText.trim().isEmpty
                            ? AppLocalizations.of(context)!
                                .photographerShootFallback
                            : request.locationText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  amount == null
                      ? '—'
                      : AppMoney.sarPhrase(amount.toStringAsFixed(0),
                          isAr: _isAr),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text((offer['details'] ?? '').toString()),
                if (offer['rating_count'] is num &&
                    (offer['rating_count'] as num) > 0)
                  Text(
                    _isAr
                        ? 'التقييم ${(offer['rating_avg'] as num?)?.toStringAsFixed(1) ?? '—'} · ${offer['rating_count']} تقييم'
                        : 'Rating ${(offer['rating_avg'] as num?)?.toStringAsFixed(1) ?? '—'} · ${offer['rating_count']} reviews',
                  ),
                const SizedBox(height: 8),
                if (actionable)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              _respondToIncomingOffer(offer, false),
                          child: Text(_isAr ? 'رفض' : 'Decline'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _respondToIncomingOffer(offer, true),
                          child: Text(
                              _isAr ? 'اختيار المصوّر' : 'Choose photographer'),
                        ),
                      ),
                    ],
                  )
                else
                  Text(_isAr ? 'حالة العرض: $status' : 'Offer status: $status'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _requesterFollowUpPane() {
    final items = _filteredShoots(
      _requesterShots.where((request) => request.status != 'open'),
    );
    if (items.isEmpty) {
      return Center(
        child: Text(
            _isAr ? 'لا توجد طلبات قيد المتابعة.' : 'No requests to track.'),
      );
    }
    return _list(
      items,
      incoming: false,
      deepLinkKeyPrefix: 'requester-track',
    );
  }

  Widget _requesterPane() {
    return Column(
      children: [
        TabBar(
          controller: _requesterTabs,
          isScrollable: false,
          labelPadding: EdgeInsets.zero,
          tabs: [
            Tab(text: _isAr ? 'طلباتي' : 'Requests'),
            Tab(text: _isAr ? 'العروض الواردة' : 'Offers'),
            Tab(text: _isAr ? 'المتابعة' : 'Tracking'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _requesterTabs,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _requesterRequestsPane(),
              _incomingOffersPane(),
              _requesterFollowUpPane(),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _submitMarketOffer(Map<String, dynamic> opportunity) async {
    final details = TextEditingController();
    final amount = TextEditingController();
    final requestId = (opportunity['request_id'] ?? '').toString();
    if (requestId.isEmpty) return;
    final accepted = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final validAmount = (double.tryParse(amount.text.trim()) ?? -1) >= 0;
          final validDetails = details.text.trim().length >= 3;
          return AlertDialog(
            title: Text(_isAr ? 'تقديم عرض تصوير' : 'Submit photo offer'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AqarTextField(
                    controller: details,
                    maxLines: 3,
                    onChanged: (_) => setLocal(() {}),
                    decoration: InputDecoration(
                      labelText: _isAr ? 'تفاصيل العرض' : 'Offer details',
                    ),
                  ),
                  const SizedBox(height: 10),
                  AqarTextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setLocal(() {}),
                    decoration: InputDecoration(
                      labelText: _isAr ? 'المبلغ بالريال' : 'Amount in SAR',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(_isAr ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton(
                onPressed: validAmount && validDetails
                    ? () => Navigator.pop(ctx, true)
                    : null,
                child: Text(_isAr ? 'إرسال العرض' : 'Send offer'),
              ),
            ],
          );
        },
      ),
    );
    final amountSar = double.tryParse(amount.text.trim());
    final offerDetails = details.text.trim();
    details.dispose();
    amount.dispose();
    if (accepted != true || amountSar == null || !mounted) return;
    try {
      await _svc.submitPhotoShootOffer(
        requestId: requestId,
        amountSar: amountSar,
        details: offerDetails,
      );
      await _reload(silent: true);
      if (!mounted) return;
      _tabs.animateTo(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isAr
              ? 'أُرسل العرض وأُضيف إلى عروضي.'
              : 'Offer sent and added to My Offers.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RpcUserMessage.of(e, isAr: _isAr))),
      );
    }
  }

  Widget _marketOpportunityCard(Map<String, dynamic> opportunity) {
    final preview = opportunity['listing_preview'] is Map
        ? Map<String, dynamic>.from(opportunity['listing_preview'] as Map)
        : const <String, dynamic>{};
    final title = (preview['title'] ?? '').toString().trim();
    final city = (opportunity['location_text'] ?? preview['city'] ?? '')
        .toString()
        .trim();
    final kinds = opportunity['shoot_kinds'] is List
        ? (opportunity['shoot_kinds'] as List).join(' · ')
        : '';
    return Card(
      key: _deepLinkCardKey('provider-request:${opportunity['request_id']}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title.isEmpty
                  ? AppLocalizations.of(context)!.photographerShootFallback
                  : title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            if (city.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(city, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 4),
            Text(kinds),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _submitMarketOffer(opportunity),
              icon: const Icon(Icons.send_outlined),
              label: Text(_isAr ? 'تقديم عرض' : 'Submit offer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _opportunitiesPane() {
    final direct = _filteredShoots(_of({'pending'}));
    final opportunities = _opportunities.where((opportunity) {
      final preview = opportunity['listing_preview'] is Map
          ? Map<String, dynamic>.from(opportunity['listing_preview'] as Map)
          : const <String, dynamic>{};
      return _matchesMyPageFilters({
        ...preview,
        'request_id': opportunity['request_id'],
        'title': preview['title'],
        'city': opportunity['location_text'] ?? preview['city'],
        'shoot_kinds': opportunity['shoot_kinds'],
      });
    }).toList();
    if (opportunities.isEmpty && direct.isEmpty) {
      return Center(
        child: Text(_opportunities.isEmpty && _of({'pending'}).isEmpty
            ? (_isAr
                ? 'لا توجد فرص تصوير متاحة الآن.'
                : 'No photo opportunities are available.')
            : (_isAr
                ? 'لا توجد فرص مطابقة لخيارات البحث.'
                : 'No opportunities match these filters.')),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final request in direct)
          Card(
            key: _deepLinkCardKey('provider-request:${request.id}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    request.locationText.trim().isEmpty
                        ? AppLocalizations.of(context)!
                            .photographerShootFallback
                        : request.locationText,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(request.shootKinds.join(' · ')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: request.acceptWindowExpired
                              ? null
                              : () => _respond(request, true),
                          child: Text(
                              AppLocalizations.of(context)!.photographerAccept),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: request.acceptWindowExpired
                              ? null
                              : () => _respond(request, false),
                          child: Text(AppLocalizations.of(context)!
                              .photographerDecline),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        for (final opportunity in opportunities)
          _marketOpportunityCard(opportunity),
      ],
    );
  }

  String _offerStatusLabel(String status) => switch (status) {
        'submitted' =>
          _isAr ? 'بانتظار قرار صاحب الطلب' : 'Awaiting requester decision',
        'accepted' => _isAr ? 'تم اختيار عرضك' : 'Offer selected',
        'declined' => _isAr ? 'مرفوض' : 'Declined',
        'not_selected' =>
          _isAr ? 'اختير عرض آخر' : 'Another offer was selected',
        _ => status,
      };

  Future<void> _showOfferTracking(Map<String, dynamic> offer) async {
    final status = (offer['offer_status'] ?? '').toString();
    final requestStatus = (offer['request_status'] ?? '').toString();
    final review = (offer['delivery_review_status'] ?? '').toString();
    final stages = <String>[
      _isAr ? 'أُرسل العرض' : 'Offer submitted',
      if (status == 'accepted' || status == 'not_selected')
        status == 'accepted'
            ? (_isAr
                ? 'اختار صاحب الطلب عرضك'
                : 'Requester selected your offer')
            : (_isAr ? 'اختير عرض آخر' : 'Another offer was selected'),
      if (requestStatus == 'accepted' || requestStatus == 'in_progress')
        _isAr ? 'العمل قيد التنفيذ' : 'Work in progress',
      if (review == 'pending_review' || review == 'approved')
        review == 'approved'
            ? (_isAr ? 'اعتمدت الملفات' : 'Media approved')
            : (_isAr ? 'الملفات بانتظار المراجعة' : 'Media awaiting review'),
    ];
    await showAppDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isAr ? 'تتبّع العرض' : 'Offer tracking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_offerStatusLabel(status)),
            const SizedBox(height: 10),
            for (final stage in stages)
              ListTile(
                dense: true,
                leading: const Icon(Icons.check_circle_outline),
                title: Text(stage),
                contentPadding: EdgeInsets.zero,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_isAr ? 'إغلاق' : 'Close'),
          ),
        ],
      ),
    );
  }

  Widget _myOffersPane() {
    final offers = _myOffers
        .where((offer) => _matchesMyPageFilters(_offerSearchRow(offer)))
        .toList();
    if (offers.isEmpty) {
      return Center(
        child: Text(_myOffers.isEmpty
            ? (_isAr
                ? 'لم ترسل عروض تصوير بعد.'
                : 'You have not sent photo offers yet.')
            : (_isAr
                ? 'لا توجد عروض مطابقة لخيارات البحث.'
                : 'No offers match these filters.')),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: offers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final offer = offers[index];
        final preview = offer['listing_preview'] is Map
            ? Map<String, dynamic>.from(offer['listing_preview'] as Map)
            : const <String, dynamic>{};
        final title = (preview['title'] ?? '').toString().trim();
        final amount = (offer['amount_sar'] as num?)?.toDouble();
        return Card(
          key: _deepLinkCardKey('provider-offer:${offer['offer_id']}'),
          child: ListTile(
            title: Text(
              title.isEmpty
                  ? AppLocalizations.of(context)!.photographerShootFallback
                  : title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${amount == null ? '—' : AppMoney.sarPhrase(amount.toStringAsFixed(0), isAr: _isAr)} · ${_offerStatusLabel((offer['offer_status'] ?? '').toString())}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: _isAr ? 'تتبّع العرض' : 'Track offer',
              onPressed: () => _showOfferTracking(offer),
              icon: const Icon(Icons.track_changes_outlined),
            ),
          ),
        );
      },
    );
  }

  Widget _profilePane() {
    final l10n = AppLocalizations.of(context)!;
    final profile = _profile!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CertifiedPhotographerName(
          name: profile.displayName,
          verified: profile.isVerified,
        ),
        const SizedBox(height: 8),
        if (profile.ratingCount > 0)
          Text(l10n.photographerRatingLine(
            profile.ratingAvg.toStringAsFixed(1),
            profile.ratingCount,
          )),
        if (profile.photoRateSar != null)
          Text(
            '${l10n.photographerPhotoRate}: ${AppMoney.sarPhrase(profile.photoRateSar!.toStringAsFixed(0), isAr: _isAr)}',
          ),
        const SizedBox(height: 8),
        Text(
          profile.portfolio.isEmpty
              ? l10n.photographerEmptyPortfolio
              : l10n.photographerFilesCount(profile.portfolio.length),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _editCap,
              icon: const Icon(Icons.tune),
              label: Text(l10n.photographerDailyCapTitle),
            ),
            OutlinedButton.icon(
              onPressed: () => showAppDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l10n.photographerTabCalendar),
                  content:
                      SizedBox(width: 440, height: 500, child: _calendar()),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(l10n.photographerDialogCancel),
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(l10n.photographerTabCalendar),
            ),
          ],
        ),
      ],
    );
  }

  Widget _providerPane(AppLocalizations l10n) {
    if (_providerLoading || (_loading && _profile == null)) {
      return const Center(child: AppLogoLoading());
    }
    if (_profile == null || !_profile!.isVerified) {
      return PhotographerJoinPage(lang: widget.lang, embedAppBar: true);
    }
    if (_subscriptionRequired) return _subscriptionRequiredPage(l10n);

    final active = _of({'accepted', 'in_progress'});
    final completed = _of({'delivered'});
    final tabs = TabBar(
      controller: _tabs,
      isScrollable: false,
      labelPadding: EdgeInsets.zero,
      tabs: [
        Tab(text: _isAr ? 'الفرص' : 'Opportunities'),
        Tab(text: _isAr ? 'عروضي' : 'My offers'),
        Tab(text: _isAr ? 'أعمالي' : 'My work'),
        Tab(text: _isAr ? 'ملفي' : 'Profile'),
      ],
    );
    return Column(
      children: [
        tabs,
        Expanded(
          child: TabBarView(
            controller: _tabs,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _opportunitiesPane(),
              _myOffersPane(),
              _list(
                [...active, ...completed],
                incoming: false,
                deepLinkKeyPrefix: 'provider-work',
              ),
              _profilePane(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _list(
    List<PhotoShootRequest> items, {
    required bool incoming,
    String? deepLinkKeyPrefix,
  }) {
    final l10n = AppLocalizations.of(context)!;
    items = _filteredShoots(items);
    if (items.isEmpty) {
      return Center(child: Text(l10n.photographerEmptyTab));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = items[i];
        final window = incoming ? _windowLabel(r, l10n) : '';
        return Card(
          key: deepLinkKeyPrefix == null
              ? null
              : _deepLinkCardKey('$deepLinkKeyPrefix:${r.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  r.listingTitle.trim().isNotEmpty
                      ? r.listingTitle
                      : r.locationText.trim().isEmpty
                          ? l10n.photographerShootFallback
                          : r.locationText,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (r.listingCity.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    r.listingCity,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (r.listingPublicCode.trim().isNotEmpty)
                  Text(
                    '${_isAr ? 'رقم الإعلان' : 'Listing'}: ${r.listingPublicCode}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(r.shootKinds.join(' · ')),
                if (r.deliveryReviewStatus == 'pending_review') ...[
                  const SizedBox(height: 8),
                  Text(
                    _isAr
                        ? 'تم التسليم — بانتظار موافقة الناشر قبل ظهوره في الإعلان.'
                        : 'Delivered — awaiting publisher approval before it appears on the listing.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                if (r.deliveryReviewStatus == 'revision_requested') ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_isAr ? 'التعديل المطلوب' : 'Requested changes'}: ${r.deliveryRevisionNote}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                if (r.quotedAmountSar != null)
                  Text(
                    '${l10n.photographerQuoteAgreed}: ${AppMoney.sarPhrase(r.quotedAmountSar!.toStringAsFixed(0), isAr: _isAr)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                if (r.preferredAt != null)
                  Text(
                    DateHelper.fmtCivilDateTime(
                      r.preferredAt!.toLocal(),
                      isAr: _isAr,
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                if (window.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    window,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: r.acceptWindowExpired
                          ? Theme.of(context).colorScheme.error
                          : const Color(0xFF0F766E),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (incoming)
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: r.acceptWindowExpired
                              ? null
                              : () => _respond(r, true),
                          child: Text(l10n.photographerAccept),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: r.acceptWindowExpired
                              ? null
                              : () => _respond(r, false),
                          child: Text(l10n.photographerDecline),
                        ),
                      ),
                    ],
                  )
                else if ((r.status == 'accepted' ||
                        r.status == 'in_progress') &&
                    r.deliveryReviewStatus != 'pending_review')
                  FilledButton.icon(
                    onPressed: () => _deliver(r),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: Text(
                      r.deliveryReviewStatus == 'revision_requested'
                          ? (_isAr ? 'إعادة إرسال الوسائط' : 'Resubmit media')
                          : l10n.photographerUploadMedia,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _calendar() {
    final l10n = AppLocalizations.of(context)!;
    final cap = _profile?.maxAcceptsPerDay ?? 5;
    final left = (cap - _acceptedToday).clamp(0, cap);
    final dayItems = _shots.where((s) {
      final at = s.preferredAt;
      if (at == null) return false;
      if (s.status == 'rejected' || s.status == 'cancelled') return false;
      return _sameDay(at.toLocal(), _calDay);
    }).toList();
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          l10n.photographerCalendarCapRemaining(left, cap),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _editCap,
            icon: const Icon(Icons.tune),
            label: Text(l10n.photographerDailyCapTitle),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 360,
          child: CalendarDatePicker(
            initialDate: _calDay,
            firstDate: DateTime(now.year - 1),
            lastDate: DateTime(now.year + 2),
            onDateChanged: (d) => setState(
              () => _calDay = DateTime(d.year, d.month, d.day),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.photographerSessionsOnDay(dayItems.length),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (dayItems.isEmpty)
          Text(l10n.photographerCalendarEmpty)
        else
          ...dayItems.map((r) {
            final t = r.preferredAt == null
                ? ''
                : DateHelper.fmtCivilDateTime(
                    r.preferredAt!.toLocal(),
                    isAr: _isAr,
                  );
            return Card(
              child: ListTile(
                title: Text(
                  r.locationText.trim().isEmpty
                      ? l10n.photographerShootFallback
                      : r.locationText,
                ),
                subtitle: Text('$t · ${r.status}'),
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final roleTabs = TabBar(
      controller: _roleTabs,
      isScrollable: false,
      labelPadding: EdgeInsets.zero,
      tabs: [
        Tab(
          icon: const Icon(Icons.home_work_outlined, size: 18),
          text: _isAr ? 'طلباتي للتصوير' : 'My photo requests',
        ),
        Tab(
          icon: const Icon(Icons.photo_camera_outlined, size: 18),
          text: _isAr ? 'أعمل كمصور' : 'Work as photographer',
        ),
      ],
    );
    final scaffold = Scaffold(
      appBar: widget.embedAppBar
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              leading: AppPageCloseButton(isArabic: _isAr),
              title: Text(l10n.photographerHubTitle),
              bottom: roleTabs,
            ),
      body: Column(
        children: [
          if (widget.embedAppBar) roleTabs,
          Expanded(
            child: TabBarView(
              controller: _roleTabs,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _requesterPane(),
                _providerPane(l10n),
              ],
            ),
          ),
        ],
      ),
    );

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: scaffold,
    );
  }
}
