import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/branding_logo_image.dart';
import '../core/gestures/app_keyboard_inset.dart';
import '../core/gestures/app_keyboard_popups.dart';
import '../core/gestures/soft_keyboard_ensure_visible.dart';
import '../core/listing/listing_media_urls.dart';
import '../core/listing/property_listing_display.dart';
import '../core/navigation/safe_overlay_pop.dart';
import '../core/shorts/shorts_canned_comments.dart';
import '../core/shorts/shorts_feed_layout.dart';
import '../core/shorts/shorts_feed_prefs.dart';
import '../core/utils/app_money.dart';
import '../l10n/app_localizations.dart';
import '../models/market_property_request_row.dart';
import '../models/property.dart';
import '../services/shorts_feed_comments_service.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/aqar_text_field.dart';
import '../widgets/shorts_feed_video_player.dart';
import '../widgets/shorts_tour_pane.dart';

/// عنصر واحد في فيد الشورتز (إعلان أو طلب سوق).
class HomeShortsItem {
  const HomeShortsItem.property(Property this.property) : request = null;

  const HomeShortsItem.request(MarketPropertyRequestRow this.request)
      : property = null;

  final Property? property;
  final MarketPropertyRequestRow? request;

  bool get isProperty => property != null;
  String get id => property?.id ?? request!.id;
}

/// شورتز بملء الشاشة: الوسائط خلف الطبقة، والأزرار والفلاتر فوقها.
class HomeShortsFeedPage extends StatefulWidget {
  const HomeShortsFeedPage({
    super.key,
    required this.items,
    required this.isAr,
    this.isGuest = false,
    this.viewerUserId = '',
    this.favoriteIds = const <String>{},
    this.mineIds = const <String>{},
    this.onReloadCatalog,
    this.onShare,
    this.onToggleFavorite,
    this.onRequireLogin,
    this.onOpenProperty,
    this.onOpenRequest,
    this.onCompleteDeal,
    this.initialIndex = 0,
  });

  final List<HomeShortsItem> items;
  final bool isAr;
  final bool isGuest;
  final String viewerUserId;
  final Set<String> favoriteIds;
  final Set<String> mineIds;
  final Future<List<HomeShortsItem>> Function()? onReloadCatalog;
  final ValueChanged<HomeShortsItem>? onShare;
  final ValueChanged<String>? onToggleFavorite;
  final VoidCallback? onRequireLogin;
  final Future<void> Function(Property)? onOpenProperty;
  final Future<void> Function(MarketPropertyRequestRow)? onOpenRequest;
  final Future<void> Function(HomeShortsItem)? onCompleteDeal;
  final int initialIndex;

  @override
  State<HomeShortsFeedPage> createState() => _HomeShortsFeedPageState();
}

class _HomeShortsFeedPageState extends State<HomeShortsFeedPage> {
  late final PageController _page;
  late int _index;
  bool _paused = false;
  bool _muted = true;
  late Set<String> _favs;
  Map<String, int> _commentCounts = {};
  int _mediaKind = 0;
  String _scope = 'all';
  String _purpose = 'all';

  @override
  void initState() {
    super.initState();
    _favs = {...widget.favoriteIds};
    _index = widget.initialIndex
        .clamp(0, (widget.items.length - 1).clamp(0, 9999));
    _page = PageController(initialPage: _index);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    unawaited(_loadCommentCounts());
    _warmAround(widget.items, _index);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _page.dispose();
    unawaited(ShortsVideoWarmPool.disposeAll());
    super.dispose();
  }

  void _togglePause() => setState(() => _paused = !_paused);

  Future<void> _stopShortsAndPop() async {
    ShortsFeedPrefs.markUserClosed();
    unawaited(ShortsFeedPrefs.setSessionActive(false));
    if (!mounted) return;
    final root = Navigator.of(context, rootNavigator: true);
    if (root.canPop() && !SafeOverlayPop.isShellRoute(SafeOverlayPop.peekTop(root))) {
      root.pop();
      return;
    }
    SafeOverlayPop.pop(context);
  }

  Future<void> _loadCommentCounts() async {
    try {
      final pIds = widget.items
          .where((e) => e.isProperty)
          .map((e) => e.id)
          .where((e) => e.isNotEmpty);
      final rIds = widget.items
          .where((e) => !e.isProperty)
          .map((e) => e.id)
          .where((e) => e.isNotEmpty);
      final p = await ShortsFeedCommentsService.countsForPropertyIds(pIds);
      final r = await ShortsFeedCommentsService.countsForRequestIds(rIds);
      if (!mounted) return;
      setState(() => _commentCounts = {...p, ...r});
    } catch (_) {}
  }

  void _warmAround(List<HomeShortsItem> items, int i) {
    for (final j in [i, i + 1]) {
      if (j < 0 || j >= items.length) continue;
      final u = _videoUrl(items[j]);
      if (u != null && u.isNotEmpty) {
        unawaited(ShortsVideoWarmPool.warm(u));
      }
    }
  }

  List<HomeShortsItem> get _visible {
    return widget.items.where((e) {
      if (_scope == 'listings' && !e.isProperty) return false;
      if (_scope == 'requests' && e.isProperty) return false;
      if (_scope == 'mine' && !widget.mineIds.contains(e.id)) return false;
      if (_purpose == 'sale' || _purpose == 'rent') {
        final rent = _itemIsRent(e);
        if (_purpose == 'rent' && !rent) return false;
        if (_purpose == 'sale' && rent) return false;
      }
      return true;
    }).toList();
  }

  void _setFilter(VoidCallback apply) {
    setState(apply);
    final vis = _visible;
    if (vis.isEmpty) {
      _index = 0;
      return;
    }
    if (_index >= vis.length) {
      _index = 0;
      if (_page.hasClients) {
        _page.jumpToPage(0);
      }
    }
  }

  bool _itemIsRent(HomeShortsItem e) {
    if (e.property != null) {
      return PropertyListingDisplay.purposeFilterKey(e.property!) == 'rent';
    }
    final p = (e.request?.purpose ?? '').toLowerCase();
    return p.contains('rent') || p.contains('إيجار');
  }

  String? _tourUrl(HomeShortsItem item) {
    final p = item.property;
    String raw = '';
    if (p != null) {
      raw = (p.virtualTourUrl ?? '').trim();
    } else {
      final d = item.request?.details ?? const <String, dynamic>{};
      for (final k in ['virtual_tour_url', 'tour_url', 'virtualTourUrl']) {
        final v = (d[k] ?? '').toString().trim();
        if (v.startsWith('http')) {
          raw = v;
          break;
        }
      }
    }
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return null;
  }

  String _toPublic(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return ListingMediaUrls.storagePublicUrl(
          Supabase.instance.client,
          s,
        ) ??
        '';
  }

  List<String> _imageUrls(HomeShortsItem item) {
    if (item.property != null) {
      return ListingMediaUrls.propertyCardImagePaths(item.property!)
          .map(_toPublic)
          .where((u) => u.isNotEmpty)
          .toList();
    }
    final cover = ListingMediaUrls.marketRequestCoverNetworkUrl(
      item.request!,
      Supabase.instance.client,
    );
    return (cover == null || cover.isEmpty) ? const [] : [cover];
  }

  String? _videoUrl(HomeShortsItem item) {
    final p = item.property;
    if (p == null) return null;
    final v = (p.videoUrl ?? '').trim();
    if (v.isEmpty) return null;
    final resolved = ListingMediaUrls.videoPlayableUrl(
      Supabase.instance.client,
      v,
    );
    return (resolved ?? '').trim().isEmpty ? null : resolved;
  }

  String _title(HomeShortsItem item) {
    return PropertyListingDisplay.shortsHeadline(
      isAr: widget.isAr,
      property: item.property,
      request: item.request,
    );
  }

  double? _priceAmount(HomeShortsItem item) {
    if (item.property != null) {
      final p = item.property!;
      return p.price > 0 ? p.price : null;
    }
    final r = item.request!;
    final max = r.budgetMax;
    final min = r.budgetMin;
    if (max != null && max > 0) return max;
    if (min != null && min > 0) return min;
    return null;
  }

  String _priceCurrency(HomeShortsItem item) =>
      (item.property?.currency ?? 'SAR').trim().isEmpty
          ? 'SAR'
          : (item.property?.currency ?? 'SAR');

  Future<void> _openItem(HomeShortsItem item) async {
    final p = item.property;
    final r = item.request;
    if (p != null) {
      await widget.onOpenProperty?.call(p);
    } else if (r != null) {
      await widget.onOpenRequest?.call(r);
    }
  }

  Future<void> _openComments(HomeShortsItem item) async {
    if (widget.isGuest) {
      widget.onRequireLogin?.call();
      return;
    }
    final added = await showAppModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: false,
      enableDrag: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _ShortsCommentsSheet(
        item: item,
        isAr: widget.isAr,
      ),
    );
    if (added != null && added > 0 && mounted) {
      setState(() {
        _commentCounts[item.id] = (_commentCounts[item.id] ?? 0) + added;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    final pad = MediaQuery.paddingOf(context);
    final layout = ShortsFeedLayout.of(MediaQuery.sizeOf(context));

    return Directionality(
      textDirection: widget.isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: items.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.isAr
                          ? 'لا توجد عقارات للعرض الآن'
                          : 'No listings to show',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppPageCloseButton(
                      isArabic: widget.isAr,
                      color: Colors.white,
                      onPressed: _stopShortsAndPop,
                    ),
                  ],
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _page,
                    scrollDirection: Axis.vertical,
                    allowImplicitScrolling: true,
                    onPageChanged: (i) => setState(() {
                      _index = i;
                      _paused = false;
                      _mediaKind = 0;
                      _warmAround(items, i);
                    }),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final imgs = _imageUrls(item);
                      final video = _videoUrl(item);
                      final tour = _tourUrl(item);
                      final showTour =
                          tour != null && tour.isNotEmpty && _mediaKind == 2;
                      final showVideo = video != null &&
                          video.isNotEmpty &&
                          _mediaKind != 2 &&
                          (tour == null || _mediaKind == 1 || imgs.isEmpty);
                      final fav = item.property != null &&
                          _favs.contains(item.property!.id);
                      final comments = _commentCounts[item.id] ?? 0;
                      final amount = _priceAmount(item);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            child: showTour
                                ? ShortsTourPane(
                                    url: tour,
                                    isAr: widget.isAr,
                                    active: i == _index,
                                  )
                                : showVideo
                                    ? ShortsFeedVideoPlayer(
                                        videoUrl: video,
                                        playing: i == _index && !_paused,
                                        muted: _muted,
                                        pooled: true,
                                      )
                                    : imgs.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: imgs.first,
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: double.infinity,
                                            alignment: Alignment.center,
                                            memCacheWidth: kIsWeb ? 900 : 1400,
                                            placeholder: (_, __) =>
                                                const ColoredBox(
                                              color: Colors.black87,
                                              child: Center(
                                                child: BrandingLogoImage(
                                                  fit: BoxFit.contain,
                                                  size: 72,
                                                ),
                                              ),
                                            ),
                                            errorWidget: (_, __, ___) =>
                                                const ColoredBox(
                                              color: Colors.black87,
                                              child: Center(
                                                child: BrandingLogoImage(
                                                  fit: BoxFit.contain,
                                                  size: 72,
                                                ),
                                              ),
                                            ),
                                          )
                                        : const ColoredBox(
                                            color: Color(0xFF0B1F1C),
                                            child: Center(
                                              child: BrandingLogoImage(
                                                fit: BoxFit.contain,
                                                size: 96,
                                              ),
                                            ),
                                          ),
                          ),
                          const IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black54,
                                    Colors.transparent,
                                    Colors.transparent,
                                    Colors.black87,
                                  ],
                                  stops: [0, 0.18, 0.58, 1],
                                ),
                              ),
                            ),
                          ),
                          if (!showTour)
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: () => unawaited(_openItem(item)),
                              ),
                            ),
                          PositionedDirectional(
                            start: 16,
                            end: 78,
                            bottom: 18 + pad.bottom,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (imgs.isNotEmpty ||
                                    video != null ||
                                    tour != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        if (imgs.isNotEmpty)
                                          _mediaChip(
                                            widget.isAr ? 'صور' : 'Photos',
                                            !showVideo && !showTour,
                                            () => setState(() => _mediaKind = 0),
                                          ),
                                        if (video != null)
                                          _mediaChip(
                                            widget.isAr ? 'فيديو' : 'Video',
                                            showVideo,
                                            () => setState(() => _mediaKind = 1),
                                          ),
                                        if (tour != null)
                                          _mediaChip(
                                            widget.isAr ? 'جولة 360' : '360 tour',
                                            showTour,
                                            () => setState(() => _mediaKind = 2),
                                          ),
                                      ],
                                    ),
                                  ),
                                IgnorePointer(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _title(item),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: layout.titleSize,
                                          height: 1.25,
                                          shadows: const [
                                            Shadow(
                                              blurRadius: 8,
                                              color: Colors.black54,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (amount != null) ...[
                                        const SizedBox(height: 8),
                                        AppMoneyLine(
                                          amount: amount,
                                          currencyCode: _priceCurrency(item),
                                          isAr: widget.isAr,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 20,
                                            shadows: [
                                              Shadow(
                                                blurRadius: 8,
                                                color: Colors.black54,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PositionedDirectional(
                            end: 4,
                            top: pad.top + 56,
                            bottom: 12 + pad.bottom,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _roundAction(
                                    icon: Icons.open_in_new_rounded,
                                    label:
                                        widget.isAr ? 'تفاصيل' : 'Open',
                                    pad: layout.actionPad,
                                    iconSize: layout.actionIcon,
                                    onTap: () => unawaited(_openItem(item)),
                                  ),
                                  SizedBox(height: layout.gap),
                                  if (item.property != null) ...[
                                    _roundAction(
                                      icon: fav
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      color: fav
                                          ? const Color(0xFFFF2D55)
                                          : Colors.white,
                                      label: widget.isAr ? 'إعجاب' : 'Like',
                                      pad: layout.actionPad,
                                      iconSize: layout.actionIcon,
                                      onTap: () {
                                        if (widget.isGuest) {
                                          widget.onRequireLogin?.call();
                                          return;
                                        }
                                        final id = item.property!.id;
                                        setState(() {
                                          if (_favs.contains(id)) {
                                            _favs.remove(id);
                                          } else {
                                            _favs.add(id);
                                          }
                                        });
                                        widget.onToggleFavorite?.call(id);
                                      },
                                    ),
                                    SizedBox(height: layout.gap),
                                  ],
                                  _roundAction(
                                    icon: Icons.mode_comment_outlined,
                                    label:
                                        widget.isAr ? 'تعليق' : 'Comment',
                                    count: comments > 0 ? comments : null,
                                    pad: layout.actionPad,
                                    iconSize: layout.actionIcon,
                                    onTap: () =>
                                        unawaited(_openComments(item)),
                                  ),
                                  SizedBox(height: layout.gap),
                                  _roundAction(
                                    icon: Icons.ios_share_rounded,
                                    label:
                                        widget.isAr ? 'مشاركة' : 'Share',
                                    pad: layout.actionPad,
                                    iconSize: layout.actionIcon,
                                    onTap: () =>
                                        widget.onShare?.call(item),
                                  ),
                                  if (!widget.mineIds.contains(item.id)) ...[
                                    SizedBox(height: layout.gap),
                                    _roundAction(
                                      icon: Icons.handshake_outlined,
                                      label: widget.isAr ? 'صفقة' : 'Deal',
                                      pad: layout.actionPad,
                                      iconSize: layout.actionIcon,
                                      onTap: () => unawaited(
                                        widget.onCompleteDeal?.call(item) ??
                                            Future<void>.value(),
                                      ),
                                    ),
                                  ],
                                  if (showVideo) ...[
                                    SizedBox(height: layout.gap),
                                    _roundAction(
                                      icon: _paused
                                          ? Icons.play_arrow_rounded
                                          : Icons.pause_rounded,
                                      label: _paused
                                          ? (widget.isAr ? 'تشغيل' : 'Play')
                                          : (widget.isAr ? 'إيقاف' : 'Pause'),
                                      pad: layout.actionPad,
                                      iconSize: layout.actionIcon,
                                      onTap: _togglePause,
                                    ),
                                    SizedBox(height: layout.gap),
                                    _roundAction(
                                      icon: _muted
                                          ? Icons.volume_off_rounded
                                          : Icons.volume_up_rounded,
                                      label:
                                          widget.isAr ? 'صوت' : 'Audio',
                                      pad: layout.actionPad,
                                      iconSize: layout.actionIcon,
                                      onTap: () =>
                                          setState(() => _muted = !_muted),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(4, pad.top + 2, 4, 8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              AppPageCloseButton(
                                isArabic: widget.isAr,
                                color: Colors.white,
                                tooltip: widget.isAr
                                    ? 'إيقاف الشورتز'
                                    : 'Close Shorts',
                                onPressed: _stopShortsAndPop,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            child: Row(
                              children: [
                                _filterChip(
                                  widget.isAr ? 'الكل' : 'All',
                                  _scope == 'all',
                                  () => _setFilter(() => _scope = 'all'),
                                ),
                                if (widget.mineIds.isNotEmpty)
                                  _filterChip(
                                    widget.isAr ? 'خاصتي' : 'Mine',
                                    _scope == 'mine',
                                    () =>
                                        _setFilter(() => _scope = 'mine'),
                                  ),
                                _filterChip(
                                  widget.isAr ? 'إعلانات' : 'Listings',
                                  _scope == 'listings',
                                  () => _setFilter(
                                      () => _scope = 'listings'),
                                ),
                                _filterChip(
                                  widget.isAr ? 'طلبات' : 'Requests',
                                  _scope == 'requests',
                                  () => _setFilter(
                                      () => _scope = 'requests'),
                                ),
                                _filterChip(
                                  widget.isAr ? 'بيع' : 'Sale',
                                  _purpose == 'sale',
                                  () => _setFilter(() {
                                    _purpose =
                                        _purpose == 'sale' ? 'all' : 'sale';
                                  }),
                                ),
                                _filterChip(
                                  widget.isAr ? 'إيجار' : 'Rent',
                                  _purpose == 'rent',
                                  () => _setFilter(() {
                                    _purpose =
                                        _purpose == 'rent' ? 'all' : 'rent';
                                  }),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Material(
        color: selected
            ? Colors.white
            : Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: selected ? Colors.black : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mediaChip(String label, bool on, VoidCallback tap) {
    return Material(
      color: on ? Colors.white : Colors.black54,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11,
              color: on ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.white,
    int? count,
    double pad = 10,
    double iconSize = 24,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsets.all(pad),
                  child: Icon(icon, color: color, size: iconSize),
                ),
              ),
            ),
            if (count != null && count > 0)
              Positioned(
                top: -4,
                right: -6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7EE0D6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
          ),
        ),
      ],
    );
  }
}

class _ShortsCommentsSheet extends StatefulWidget {
  const _ShortsCommentsSheet({
    required this.item,
    required this.isAr,
  });

  final HomeShortsItem item;
  final bool isAr;

  @override
  State<_ShortsCommentsSheet> createState() => _ShortsCommentsSheetState();
}

class _ShortsCommentsSheetState extends State<_ShortsCommentsSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  List<ShortsFeedComment> _rows = const [];
  bool _loading = true;
  int _added = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        AppSoftKeyboardEnsureVisible.scheduleEnsureVisible();
      }
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await ShortsFeedCommentsService.load(
      isProperty: widget.item.isProperty,
      id: widget.item.id,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _send([String? canned]) async {
    final body = (canned ?? _ctrl.text).trim();
    if (body.isEmpty) return;
    final added = await ShortsFeedCommentsService.add(
      isProperty: widget.item.isProperty,
      id: widget.item.id,
      body: body,
    );
    if (!mounted) return;
    if (added == null) return;
    _ctrl.clear();
    setState(() {
      _rows = [added, ..._rows];
      _added += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kbOpen = AppKeyboardInset.isOpen(context);
    final pad = MediaQuery.paddingOf(context);
    final rent = widget.item.property != null
        ? PropertyListingDisplay.purposeFilterKey(widget.item.property!) ==
            'rent'
        : ((widget.item.request?.purpose ?? '').toLowerCase().contains('rent') ||
            (widget.item.request?.purpose ?? '').contains('إيجار'));
    final canned = ShortsCannedComments.forItem(
      isAr: widget.isAr,
      isProperty: widget.item.isProperty,
      isRent: rent,
    );
    return SizedBox.expand(
      child: Padding(
        padding: EdgeInsets.only(
          top: pad.top,
          bottom: kbOpen ? 0 : pad.bottom,
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n?.shortsCommentsTitle ??
                          (widget.isAr ? 'التعليقات' : 'Comments'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  AppPageCloseButton(
                    color: Colors.white70,
                    onPressed: () => Navigator.pop(context, _added),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white70),
                    )
                  : _rows.isEmpty
                      ? Center(
                          child: Text(
                            l10n?.shortsCommentEmpty ??
                                (widget.isAr
                                    ? 'لا تعليقات بعد'
                                    : 'No comments yet'),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView.builder(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          itemCount: _rows.length,
                          itemBuilder: (_, i) {
                            final c = _rows[i];
                            final name = c.authorLabel.trim().isNotEmpty
                                ? c.authorLabel.trim()
                                : (l10n?.shortsCommenterFallback ??
                                    (widget.isAr
                                        ? 'شريك مهتم'
                                        : 'Interested partner'));
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF7EE0D6),
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      if (c.mine) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white12,
                                            borderRadius:
                                                BorderRadius.circular(99),
                                          ),
                                          child: Text(
                                            l10n?.shortsCommenterMyDeal ??
                                                (widget.isAr
                                                    ? 'صفقتي'
                                                    : 'My deal'),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    c.body,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: canned.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  return ActionChip(
                    label: Text(
                      canned[i],
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => unawaited(_send(canned[i])),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: AqarTextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: l10n?.shortsCommentHint ??
                            (widget.isAr ? 'اكتب تعليقاً' : 'Write a comment'),
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                      ),
                      onSubmitted: (_) => unawaited(_send()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => unawaited(_send()),
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
