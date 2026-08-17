import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/branding_logo_image.dart';
import '../core/listing/listing_media_urls.dart';
import '../core/listing/property_listing_display.dart';
import '../core/utils/app_money.dart';
import '../models/market_property_request_row.dart';
import '../models/property.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/inline_property_video.dart';

/// عنصر واحد في فيد الشورتز (إعلان أو طلب سوق).
class HomeShortsItem {
  const HomeShortsItem.property(Property this.property) : request = null;

  const HomeShortsItem.request(MarketPropertyRequestRow this.request)
      : property = null;

  final Property? property;
  final MarketPropertyRequestRow? request;

  bool get isProperty => property != null;
}

/// شورتز بملء الشاشة بأسلوب تيك توك — صور/فيديو العقار الحقيقية + إيقاف/تشغيل.
class HomeShortsFeedPage extends StatefulWidget {
  const HomeShortsFeedPage({
    super.key,
    required this.items,
    required this.isAr,
    this.onOpenProperty,
    this.onOpenRequest,
    this.onCompleteDeal,
    this.initialIndex = 0,
  });

  final List<HomeShortsItem> items;
  final bool isAr;
  final ValueChanged<Property>? onOpenProperty;
  final ValueChanged<MarketPropertyRequestRow>? onOpenRequest;
  final ValueChanged<HomeShortsItem>? onCompleteDeal;
  final int initialIndex;

  @override
  State<HomeShortsFeedPage> createState() => _HomeShortsFeedPageState();
}

class _HomeShortsFeedPageState extends State<HomeShortsFeedPage> {
  late final PageController _page;
  late int _index;
  bool _paused = false;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, (widget.items.length - 1).clamp(0, 9999));
    _page = PageController(initialPage: _index);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _page.dispose();
    super.dispose();
  }

  void _togglePause() => setState(() => _paused = !_paused);

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
    if (item.property != null) {
      return PropertyListingDisplay.displayListingTitle(
        item.property!,
        widget.isAr,
      );
    }
    return PropertyListingDisplay.displayRequestTitle(
      item.request!,
      widget.isAr,
    );
  }

  String _priceLine(HomeShortsItem item) {
    if (item.property != null) {
      final p = item.property!;
      if (p.price <= 0) return '';
      return AppMoney.formatWithCurrencyCode(
        p.price,
        isAr: widget.isAr,
        currencyCode: p.currency,
      );
    }
    final r = item.request!;
    final max = r.budgetMax;
    final min = r.budgetMin;
    if (max != null && max > 0) {
      return AppMoney.formatWithCurrencyCode(max, isAr: widget.isAr);
    }
    if (min != null && min > 0) {
      return AppMoney.formatWithCurrencyCode(min, isAr: widget.isAr);
    }
    return '';
  }

  String _kindLabel(HomeShortsItem item) => item.isProperty
      ? (widget.isAr ? 'إعلان عقار' : 'Listing')
      : (widget.isAr ? 'طلب سوق' : 'Market request');

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final cs = Theme.of(context).colorScheme;

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
                      onPressed: () => Navigator.of(context).maybePop(),
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
                    }),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final imgs = _imageUrls(item);
                      final video = _videoUrl(item);
                      final showVideo =
                          video != null && video.isNotEmpty && imgs.isEmpty;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          if (showVideo && !_paused)
                            InlinePropertyVideoPlayer(
                              videoUrl: video,
                              isAr: widget.isAr,
                            )
                          else if (imgs.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: imgs.first,
                              fit: BoxFit.cover,
                              memCacheWidth: kIsWeb ? 900 : 1400,
                              placeholder: (_, __) => const ColoredBox(
                                color: Colors.black87,
                                child: Center(
                                  child: BrandingLogoImage(
                                    fit: BoxFit.contain,
                                    size: 72,
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) => const ColoredBox(
                                color: Colors.black87,
                                child: Center(
                                  child: BrandingLogoImage(
                                    fit: BoxFit.contain,
                                    size: 72,
                                  ),
                                ),
                              ),
                            )
                          else
                            const ColoredBox(
                              color: Color(0xFF0B1F1C),
                              child: Center(
                                child: BrandingLogoImage(
                                  fit: BoxFit.contain,
                                  size: 96,
                                ),
                              ),
                            ),
                          // تدرج سفلي للنص
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.transparent,
                                  Colors.black54,
                                  Colors.black87,
                                ],
                                stops: [0, 0.45, 0.75, 1],
                              ),
                            ),
                          ),
                          if (_paused)
                            Center(
                              child: Icon(
                                Icons.play_circle_fill_rounded,
                                size: 84,
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                            ),
                          PositionedDirectional(
                            start: 16,
                            end: 88,
                            bottom: 28 + MediaQuery.paddingOf(context).bottom,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _kindLabel(item),
                                  style: TextStyle(
                                    color: cs.primaryContainer,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _title(item),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                    height: 1.25,
                                  ),
                                ),
                                if (_priceLine(item).isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _priceLine(item),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 22,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          PositionedDirectional(
                            end: 10,
                            bottom: 36 + MediaQuery.paddingOf(context).bottom,
                            child: Column(
                              children: [
                                _roundAction(
                                  icon: Icons.info_outline_rounded,
                                  label: widget.isAr ? 'تفاصيل' : 'Details',
                                  onTap: () {
                                    if (item.property != null) {
                                      widget.onOpenProperty?.call(item.property!);
                                    } else if (item.request != null) {
                                      widget.onOpenRequest?.call(item.request!);
                                    }
                                  },
                                ),
                                const SizedBox(height: 14),
                                _roundAction(
                                  icon: Icons.handshake_outlined,
                                  label: widget.isAr ? 'إتمام' : 'Deal',
                                  onTap: () =>
                                      widget.onCompleteDeal?.call(item),
                                ),
                                const SizedBox(height: 14),
                                _roundAction(
                                  icon: _muted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  label: widget.isAr ? 'صوت' : 'Audio',
                                  onTap: () =>
                                      setState(() => _muted = !_muted),
                                ),
                              ],
                            ),
                          ),
                          // لمس الوسط = إيقاف/تشغيل (بدون اعتراض أزرار الجانب)
                          Positioned(
                            left: 72,
                            right: 72,
                            top: 80,
                            bottom: 120,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: _togglePause,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: Row(
                        children: [
                          AppPageCloseButton(
                            isArabic: widget.isAr,
                            color: Colors.white,
                            tooltip: widget.isAr ? 'إيقاف الشورتز' : 'Close Shorts',
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          const Spacer(),
                          if (items.length > 1)
                            Text(
                              widget.isAr
                                  ? 'مرّر للأعلى للعقار التالي'
                                  : 'Swipe up for next',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          const Spacer(),
                          IconButton(
                            tooltip: _paused
                                ? (widget.isAr ? 'تشغيل' : 'Play')
                                : (widget.isAr ? 'إيقاف' : 'Pause'),
                            onPressed: _togglePause,
                            icon: Icon(
                              _paused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              color: Colors.white,
                              size: 28,
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

  Widget _roundAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.black45,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
