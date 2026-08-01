import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/branding/aqar_brand_colors.dart';
import '../core/config/app_config.dart';
import '../core/branding/branding_logo_image.dart';
import '../core/listing/listing_media_urls.dart';
import '../core/listing/property_listing_display.dart';
import '../core/listing/property_type_catalog.dart';
import '../core/location/map_picker_geolocation.dart';
import '../core/market/instant_market_request_feed.dart';
import '../core/utils/app_money.dart';
import '../core/workflow/listing_workflow_stage.dart';
import '../models/market_property_request_row.dart';
import '../models/property.dart';
import '../widgets/instant_market_request_badge.dart';

/// طابع خريطة هادئ يُبرز الدبابيس دون ازدحام POI.
const String _kElegantMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#f2f7f5"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#3d5a52"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#f7fbf9"}]},
  {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#c5d8d1"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#d8eee6"},{"visibility":"on"}]},
  {"featureType":"poi.park","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#d7e6e0"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#e8f2ee"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#b9d2c8"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#c9e4f0"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#5a7a8a"}]}
]
''';

bool propertyEligibleForPublicMap(Property p) {
  if (p.deletedByUser || p.deleteApproved) return false;
  final st = p.normalizedStatus;
  if (const {'sold', 'completed', 'deleted', 'closed', 'archived'}
      .contains(st)) {
    return false;
  }
  final stage = ListingWorkflowStage.resolve(
    workflowStage: p.workflowStage,
    legacyStatus: p.status,
    publishedAt: p.publishedAt,
  );
  return !const {
    ListingWorkflowStage.archived,
    ListingWorkflowStage.terminated,
    ListingWorkflowStage.cancelled,
    ListingWorkflowStage.contractCancelled,
  }.contains(stage);
}

bool marketRequestEligibleForPublicMap(MarketPropertyRequestRow r) {
  if (r.completedAt != null) return false;
  final s = r.status.trim().toLowerCase();
  if (const {
    'completed',
    'archived',
    'closed',
    'cancelled',
    'canceled',
    'fulfilled',
    'done',
    'sold',
  }.contains(s)) {
    return false;
  }
  if (r.deletionRequestedAt != null) return false;
  return true;
}

enum MapDiscoveryKind { all, listings, requests }

class PropertyMapDiscoveryPage extends StatefulWidget {
  const PropertyMapDiscoveryPage({
    super.key,
    required this.isAr,
    this.embedAppBar = false,
    this.properties = const <Property>[],
    this.requests = const <MarketPropertyRequestRow>[],
    this.focusProperty,
    this.focusRequest,
    this.onOpenProperty,
    this.onOpenRequest,
    this.requestCoverImageUrl,
    this.listingsOnly = false,
    this.contextTitle,
    this.initialKind = MapDiscoveryKind.all,
  });

  final bool isAr;
  /// عند `true`: لا سهم رجوع داخلي — يعتمد على الشريط العلوي للداشبورد.
  final bool embedAppBar;
  final List<Property> properties;
  final List<MarketPropertyRequestRow> requests;
  final Property? focusProperty;
  final MarketPropertyRequestRow? focusRequest;
  final ValueChanged<Property>? onOpenProperty;
  final ValueChanged<MarketPropertyRequestRow>? onOpenRequest;

  /// غلاف طلب السوق من `property-images` كرابط عام (اختياري).
  final String? Function(MarketPropertyRequestRow row)? requestCoverImageUrl;

  /// عند `true`: خفِّ كلَّ الطلبات وأبقِ الإعلانات فقط — يُستخدم من تبويبات
  /// «صفحتي» للمالك/المسوّق حيث المطلوب عرض الإعلانات حصراً على الخريطة.
  final bool listingsOnly;

  /// عنوان سياق إضافي يظهر بجوار «خريطة العقارات» (مثلاً: «تبويب السوق»
  /// أو «إعلاناتي»). يُستخدم لتوضيح الموضع الذي فتح الخريطة منه.
  final String? contextTitle;

  /// فلتر أولي من الرئيسية (الكل / إعلانات / طلبات).
  final MapDiscoveryKind initialKind;

  @override
  State<PropertyMapDiscoveryPage> createState() =>
      _PropertyMapDiscoveryPageState();
}

class _PropertyMapDiscoveryPageState extends State<PropertyMapDiscoveryPage> {
  static const LatLng _saudiCenter = LatLng(23.993165, 45.078064);

  GoogleMapController? _controller;
  MapDiscoveryKind _kind = MapDiscoveryKind.all;
  _MapDiscoveryEntry? _selected;
  Set<Marker> _markers = const <Marker>{};
  bool _buildingMarkers = true;
  bool _locating = false;
  String? _mapHint;
  bool _cardCollapsed = false;

  /// عادي / قمري / تضاريس / هجين. الافتراضي «عادي» احتراماً لتجربة المستخدم.
  MapType _mapType = MapType.normal;

  bool get _isAr => widget.isAr;

  @override
  void initState() {
    super.initState();
    if (widget.listingsOnly) {
      _kind = MapDiscoveryKind.listings;
    } else {
      _kind = widget.initialKind;
    }
    _selected = _initialSelection();
    unawaited(_rebuildMarkers());
  }

  @override
  void didUpdateWidget(covariant PropertyMapDiscoveryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.properties != widget.properties ||
        oldWidget.requests != widget.requests ||
        oldWidget.focusProperty != widget.focusProperty ||
        oldWidget.focusRequest != widget.focusRequest ||
        oldWidget.requestCoverImageUrl != widget.requestCoverImageUrl) {
      _selected ??= _initialSelection();
      unawaited(_rebuildMarkers());
    }
  }

  List<_MapDiscoveryEntry> get _allEntries {
    return <_MapDiscoveryEntry>[
      ...widget.properties
          .where(
            (p) => widget.listingsOnly || propertyEligibleForPublicMap(p),
          )
          .map((p) => _MapDiscoveryEntry.fromProperty(p, isAr: _isAr))
          .whereType<_MapDiscoveryEntry>(),
      if (!widget.listingsOnly) ...[
        ...(() {
          final reqs = widget.requests
              .where(marketRequestEligibleForPublicMap)
              .toList()
            ..sort(InstantMarketRequestFeed.compare);
          return reqs
              .map(
                (r) => _MapDiscoveryEntry.fromRequest(
                  r,
                  isAr: _isAr,
                  coverPublicUrl: widget.requestCoverImageUrl?.call(r),
                ),
              )
              .whereType<_MapDiscoveryEntry>();
        })(),
      ],
    ];
  }

  List<_MapDiscoveryEntry> get _visibleEntries {
    final all = _allEntries;
    final effectiveKind =
        widget.listingsOnly ? MapDiscoveryKind.listings : _kind;
    return all.where((e) {
      return switch (effectiveKind) {
        MapDiscoveryKind.all => true,
        MapDiscoveryKind.listings => e.property != null,
        MapDiscoveryKind.requests => e.request != null,
      };
    }).toList(growable: false);
  }

  _MapDiscoveryEntry? _initialSelection() {
    final fp = widget.focusProperty;
    if (fp != null) return _MapDiscoveryEntry.fromProperty(fp, isAr: _isAr);
    final fr = widget.focusRequest;
    if (fr != null) {
      return _MapDiscoveryEntry.fromRequest(
        fr,
        isAr: _isAr,
        coverPublicUrl: widget.requestCoverImageUrl?.call(fr),
      );
    }
    return null;
  }

  LatLng get _initialTarget {
    final s = _selected;
    if (s != null) return s.position;
    final vis = _visibleEntries;
    if (vis.isEmpty) return _saudiCenter;
    var lat = 0.0;
    var lng = 0.0;
    for (final e in vis) {
      lat += e.position.latitude;
      lng += e.position.longitude;
    }
    final n = vis.length;
    return LatLng(lat / n, lng / n);
  }

  double _initialZoom() {
    if (_selected != null) return 13.5;
    final vis = _visibleEntries;
    if (vis.length <= 1) return 5.2;
    return 4.85;
  }

  Future<void> _rebuildMarkers() async {
    final entries = _visibleEntries;
    if (mounted) setState(() => _buildingMarkers = true);
    final markers = <Marker>{};
    for (final e in entries) {
      final selected = _selected?.key == e.key;
      markers.add(
        Marker(
          markerId: MarkerId(e.key),
          position: e.position,
          icon: await _priceMarkerIcon(
            priceLine: e.mapMarkerPriceLine(isAr: _isAr),
            titleLine: e.mapMarkerTitleLine(isAr: _isAr),
            placeLine: e.mapMarkerPlaceLine(isAr: _isAr),
            isRequest: e.request != null,
            isInstantRequest: e.isInstantRequest,
            selected: selected,
            isAr: _isAr,
            isSold: e.isSold,
            isReserved: e.isReserved,
          ),
          anchor: const Offset(0.5, 1.0),
          onTap: () => _onMarkerTap(e),
          infoWindow: InfoWindow.noText,
          zIndex: selected ? 2 : 1,
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _markers = markers;
      _buildingMarkers = false;
    });
    _scheduleFitCameraToEntries();
  }

  /// لمسة أولى على الدبّوس تُظهر بطاقة التفاصيل المبسّطة. لمسة ثانية على نفس
  /// الدبّوس خلال 1.4 ثانية تفتح التفاصيل الكاملة فوراً — اختصار «ذكي» يطابق
  /// التوقّع الطبيعي بأن التركيز المكرّر يعني «أريد المزيد».
  DateTime? _lastMarkerTapAt;
  String? _lastMarkerTapKey;

  void _onMarkerTap(_MapDiscoveryEntry e) {
    final now = DateTime.now();
    final isDoubleTap = _lastMarkerTapKey == e.key &&
        _lastMarkerTapAt != null &&
        now.difference(_lastMarkerTapAt!).inMilliseconds < 1400;
    _lastMarkerTapAt = now;
    _lastMarkerTapKey = e.key;

    if (isDoubleTap) {
      _openSelectedDetails(e);
      return;
    }

    setState(() {
      _selected = e;
      _cardCollapsed = false;
    });
    unawaited(_rebuildMarkers());
    unawaited(
      _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(e.position, 14.35),
      ),
    );
  }

  void _scheduleFitCameraToEntries() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final c = _controller;
      if (c == null) return;
      final pts = _visibleEntries.map((e) => e.position).toList();
      if (pts.isEmpty) return;
      try {
        if (pts.length == 1) {
          await c.animateCamera(
            CameraUpdate.newLatLngZoom(pts.first, 14.25),
          );
          return;
        }
        var minLat = pts.first.latitude;
        var maxLat = minLat;
        var minLng = pts.first.longitude;
        var maxLng = minLng;
        for (final p in pts.skip(1)) {
          minLat = math.min(minLat, p.latitude);
          maxLat = math.max(maxLat, p.latitude);
          minLng = math.min(minLng, p.longitude);
          maxLng = math.max(maxLng, p.longitude);
        }
        const pad = 0.05;
        await c.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(minLat - pad, minLng - pad),
              northeast: LatLng(maxLat + pad, maxLng + pad),
            ),
            52,
          ),
        );
      } catch (_) {
        try {
          await c.animateCamera(
            CameraUpdate.newLatLngZoom(_initialTarget, 10.5),
          );
        } catch (_) {}
      }
    });
  }

  Future<void> _focusEntry(_MapDiscoveryEntry e, {double zoom = 15.25}) async {
    setState(() => _selected = e);
    try {
      await _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(e.position, zoom),
      );
    } catch (_) {}
    await _rebuildMarkers();
  }

  void _openSelectedDetails(_MapDiscoveryEntry entry) {
    final p = entry.property;
    final r = entry.request;
    if (p != null) {
      widget.onOpenProperty?.call(p);
    } else if (r != null) {
      widget.onOpenRequest?.call(r);
    }
  }

  Future<void> _locateMe() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _mapHint = null;
    });
    try {
      final outcome = await detectMapPickerLocation(isWeb: kIsWeb);
      final pos = outcome.position;
      if (outcome.status == MapPickerLocateStatus.ok && pos != null) {
        await _controller?.animateCamera(CameraUpdate.newLatLngZoom(pos, 14));
        if (mounted) {
          setState(() {
            _mapHint = _isAr
                ? 'تم تقريب الخريطة حول موقعك الحالي.'
                : 'Map centered around your current location.';
          });
        }
      } else if (mounted) {
        setState(() {
          _mapHint = _isAr
              ? 'لم يتم السماح بالموقع. يمكنك الاستمرار بتحريك الخريطة يدويًا.'
              : 'Location was not allowed. You can still explore manually.';
        });
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _applyElegantMapStyle() async {
    final c = _controller;
    if (c == null) return;
    try {
      if (_mapType == MapType.normal) {
        await c.setMapStyle(_kElegantMapStyle);
      } else {
        await c.setMapStyle(null);
      }
    } catch (_) {}
  }

  Future<BitmapDescriptor> _priceMarkerIcon({
    required String priceLine,
    required String titleLine,
    required String placeLine,
    required bool isRequest,
    required bool isInstantRequest,
    required bool selected,
    required bool isAr,
    bool isSold = false,
    bool isReserved = false,
  }) async {
    const dpr = 2.0;
    final tdir = isAr ? TextDirection.rtl : TextDirection.ltr;
    const fontFamily = 'Cairo';

    final baseColor = isSold
        ? const Color(0xFF64748B)
        : isReserved
            ? const Color(0xFFD97706)
            : isInstantRequest
                ? AqarBrandColors.alertRed
                : isRequest
                    ? const Color(0xFF6D28D9)
                    : AqarBrandColors.primary;
    final topColor = Color.lerp(baseColor, Colors.white, 0.14)!;
    final ink = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.88);

    TextPainter paintLine(
      String text, {
      required double fontSize,
      required FontWeight weight,
      required Color color,
      double maxWidth = 220,
    }) {
      final t = text.trim().isEmpty ? '—' : text.trim();
      final painter = TextPainter(
        text: TextSpan(
          text: t,
          style: TextStyle(
            color: color,
            fontSize: fontSize * dpr,
            fontWeight: weight,
            fontFamily: fontFamily,
            height: 1.15,
            letterSpacing: isAr ? 0 : 0.1,
          ),
        ),
        textDirection: tdir,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth * dpr);
      return painter;
    }

    final badgeText = isSold
        ? (isAr ? 'مبيوع' : 'SOLD')
        : isReserved
            ? (isAr ? 'محجوز' : 'RSVD')
            : isInstantRequest
                ? (isAr ? 'فوري' : 'NOW')
                : (isRequest
                    ? (isAr ? 'طلب' : 'REQ')
                    : (isAr ? 'إعلان' : 'AD'));

    final pBadge = paintLine(
      badgeText,
      fontSize: selected ? 9.5 : 9.0,
      weight: FontWeight.w800,
      color: ink,
      maxWidth: 72,
    );
    final pPrice = paintLine(
      priceLine,
      fontSize: selected ? 14.5 : 13.2,
      weight: FontWeight.w900,
      color: ink,
      maxWidth: 168,
    );
    final pTitle = paintLine(
      titleLine,
      fontSize: selected ? 11.4 : 10.6,
      weight: FontWeight.w700,
      color: ink,
      maxWidth: 200,
    );
    final pPlace = paintLine(
      placeLine,
      fontSize: selected ? 10.2 : 9.5,
      weight: FontWeight.w600,
      color: muted,
      maxWidth: 200,
    );

    final contentW = math.max(
      pPrice.width + pBadge.width + 48 * dpr,
      math.max(pTitle.width, pPlace.width),
    );
    final width =
        (math.min(260.0, math.max(128.0, contentW / dpr + 28)) * dpr);
    final tipH = 14.0 * dpr;
    final padX = 12.0 * dpr;
    final padTop = 9.0 * dpr;
    final gap = 3.2 * dpr;
    final bubbleH = padTop +
        pPrice.height +
        gap +
        pTitle.height +
        gap +
        pPlace.height +
        10 * dpr;
    final height = bubbleH + tipH;
    final radius = (selected ? 18.0 : 16.0) * dpr;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: selected ? 0.26 : 0.18)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * dpr);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3 * dpr, 4 * dpr, width - 6 * dpr, bubbleH - 2 * dpr),
        Radius.circular(radius),
      ),
      shadowPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(width / 2, height - 2 * dpr),
        width: 18 * dpr,
        height: 6 * dpr,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.2),
    );

    final cardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, bubbleH),
      Radius.circular(radius),
    );

    // بطاقة ملوّنة بهوية النوع (ليست بيضاء) + نص أبيض واضح
    canvas.drawRRect(
      cardRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, bubbleH),
          [topColor, baseColor],
        ),
    );
    canvas.drawRRect(
      cardRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (selected ? 2.8 : 1.6) * dpr
        ..color = selected
            ? AqarBrandColors.gold
            : Colors.white.withValues(alpha: 0.92),
    );

    final badgePadX = 7 * dpr;
    final badgeH = pBadge.height + 5 * dpr;
    final badgeW = pBadge.width + badgePadX * 2;
    final badgeR = RRect.fromRectAndRadius(
      Rect.fromLTWH(padX, padTop - 1 * dpr, badgeW, badgeH),
      Radius.circular(999),
    );
    canvas.drawRRect(
      badgeR,
      Paint()..color = Colors.white.withValues(alpha: 0.22),
    );
    pBadge.paint(
      canvas,
      Offset(padX + badgePadX, padTop + (badgeH - pBadge.height) / 2 - 1 * dpr),
    );

    final priceY = padTop + (badgeH - pPrice.height) / 2;
    pPrice.paint(
      canvas,
      Offset(width - padX - pPrice.width, priceY),
    );

    final titleY = padTop + badgeH + gap + 1 * dpr;
    pTitle.paint(canvas, Offset((width - pTitle.width) / 2, titleY));
    final placeY = titleY + pTitle.height + gap;
    pPlace.paint(canvas, Offset((width - pPlace.width) / 2, placeY));

    final tipPath = Path()
      ..moveTo(width / 2 - 9 * dpr, bubbleH - 1 * dpr)
      ..lineTo(width / 2, height - 1 * dpr)
      ..lineTo(width / 2 + 9 * dpr, bubbleH - 1 * dpr)
      ..close();
    canvas.drawPath(tipPath, Paint()..color = baseColor);
    canvas.drawPath(
      tipPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * dpr
        ..color = selected
            ? AqarBrandColors.gold
            : Colors.white.withValues(alpha: 0.85),
    );

    if (selected) {
      canvas.drawCircle(
        Offset(width - 11 * dpr, 12 * dpr),
        3.4 * dpr,
        Paint()..color = AqarBrandColors.gold,
      );
      canvas.drawCircle(
        Offset(width - 11 * dpr, 12 * dpr),
        1.6 * dpr,
        Paint()..color = Colors.white,
      );
    }

    final image = await recorder.endRecording().toImage(
      width.ceil(),
      height.ceil(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    return BitmapDescriptor.bytes(
      bytes,
      imagePixelRatio: dpr,
    );
  }

  void _setKind(MapDiscoveryKind kind) {
    // ضغطة ثانية على نفس الفلتر تُنهيه وتعود للكل.
    final next = (!widget.listingsOnly && _kind == kind)
        ? MapDiscoveryKind.all
        : kind;
    setState(() {
      _kind = next;
      final visible = _visibleEntries;
      if (_selected == null ||
          !visible.any((entry) => entry.key == _selected!.key)) {
        _selected = visible.firstOrNull;
      }
    });
    unawaited(_rebuildMarkers());
    final target = _selected?.position;
    if (target != null) {
      unawaited(_controller?.animateCamera(
        CameraUpdate.newLatLngZoom(target, 12.5),
      ));
    }
  }

  Future<void> _openExternal(_MapDiscoveryEntry e) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query='
      '${e.position.latitude},${e.position.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _kindLabel(MapDiscoveryKind kind) {
    return switch (kind) {
      MapDiscoveryKind.all => _isAr ? 'الكل' : 'All',
      MapDiscoveryKind.listings => _isAr ? 'الإعلانات' : 'Listings',
      MapDiscoveryKind.requests => _isAr ? 'الطلبات' : 'Requests',
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = _visibleEntries;
    final w = MediaQuery.sizeOf(context).width;
    final isCompact = w < 720;
    // ارتفاع البطاقة المتوقّع لتعديل موضع زر «موقعي» حتى لا يتقاطعا.
    final selectedCardSpace = _selected == null
        ? 16.0
        : (_cardCollapsed ? 86.0 : (isCompact ? 196.0 : 178.0));

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.embedAppBar,
          title: Text(
            widget.contextTitle == null || widget.contextTitle!.trim().isEmpty
                ? (_isAr ? 'خريطة العقارات' : 'Property map')
                : (_isAr
                    ? 'خريطة — ${widget.contextTitle}'
                    : 'Map — ${widget.contextTitle}'),
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: entries.isEmpty
                  ? _EmptyMapState(isAr: _isAr)
                  : GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _initialTarget,
                        zoom: _initialZoom(),
                      ),
                      markers: _markers,
                      mapType: _mapType,
                      onMapCreated: (c) {
                        _controller = c;
                        unawaited(_applyElegantMapStyle());
                        _scheduleFitCameraToEntries();
                      },
                      myLocationButtonEnabled: false,
                      mapToolbarEnabled: false,
                      zoomControlsEnabled: false,
                      compassEnabled: true,
                      rotateGesturesEnabled: true,
                      tiltGesturesEnabled: true,
                      zoomGesturesEnabled: true,
                      scrollGesturesEnabled: true,
                    ),
            ),
            PositionedDirectional(
              top: 12,
              start: 12,
              end: 12,
              child: SafeArea(
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(999),
                  color: cs.surface.withValues(alpha: 0.94),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        for (final kind in MapDiscoveryKind.values
                            .where((k) =>
                                !widget.listingsOnly ||
                                k == MapDiscoveryKind.listings))
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: ChoiceChip(
                                selected: widget.listingsOnly
                                    ? kind == MapDiscoveryKind.listings
                                    : _kind == kind,
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _kindLabel(kind),
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                ),
                                avatar: Icon(
                                  kind == MapDiscoveryKind.requests
                                      ? Icons.request_quote_outlined
                                      : kind == MapDiscoveryKind.listings
                                          ? Icons.apartment_outlined
                                          : Icons.layers_outlined,
                                  size: 16,
                                ),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                onSelected: widget.listingsOnly
                                    ? null
                                    : (_) => _setKind(kind),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_buildingMarkers)
              const PositionedDirectional(
                top: 74,
                start: 16,
                end: 16,
                child: LinearProgressIndicator(minHeight: 2),
              ),
            // مبدّل نوع الخريطة (عادي / قمري / تضاريس / هجين) — على الحافة المقابلة
            // لزر «موقعي» لمنع التداخل.
            PositionedDirectional(
              start: 12,
              bottom: selectedCardSpace +
                  MediaQuery.viewPaddingOf(context).bottom,
              child: SafeArea(
                child: _MapTypeToggle(
                  isAr: _isAr,
                  value: _mapType,
                  onChanged: (t) {
                    setState(() => _mapType = t);
                    unawaited(_applyElegantMapStyle());
                  },
                ),
              ),
            ),
            PositionedDirectional(
              end: 12,
              bottom: selectedCardSpace +
                  MediaQuery.viewPaddingOf(context).bottom,
              child: SafeArea(
                child: FloatingActionButton.small(
                  heroTag: 'mapDiscoveryLocateMe',
                  onPressed: _locating ? null : _locateMe,
                  tooltip: _isAr ? 'موقعي الحالي' : 'My location',
                  child: _locating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_outlined),
                ),
              ),
            ),
            if (_mapHint != null)
              PositionedDirectional(
                top: 70,
                start: 12,
                end: 12,
                child: SafeArea(
                  child: Material(
                    elevation: 6,
                    color: cs.inverseSurface.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        _mapHint!,
                        style: TextStyle(
                          color: cs.onInverseSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_selected != null)
              PositionedDirectional(
                start: 12,
                end: 12,
                bottom: 12 + MediaQuery.viewPaddingOf(context).bottom,
                child: _MapDiscoveryCard(
                  entry: _selected!,
                  isAr: _isAr,
                  colorScheme: cs,
                  collapsed: _cardCollapsed,
                  onToggleCollapse: () {
                    setState(() => _cardCollapsed = !_cardCollapsed);
                  },
                  onDismiss: () {
                    setState(() {
                      _selected = null;
                      _cardCollapsed = false;
                    });
                    unawaited(_rebuildMarkers());
                  },
                  onOpenExternal: () => _openExternal(_selected!),
                  onOpenDetails: () => _openSelectedDetails(_selected!),
                  hasDetailsAction: (_selected!.property != null &&
                          widget.onOpenProperty != null) ||
                      (_selected!.request != null &&
                          widget.onOpenRequest != null),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MapDiscoveryEntry {
  const _MapDiscoveryEntry({
    required this.key,
    required this.position,
    required this.title,
    required this.city,
    required this.amountLabel,
    required this.typeLabel,
    required this.imageUrl,
    this.property,
    this.request,
    this.isSold = false,
    this.isReserved = false,
  });

  final String key;
  final LatLng position;
  final String title;
  final String city;
  final String amountLabel;
  final String typeLabel;
  final String imageUrl;
  final Property? property;
  final MarketPropertyRequestRow? request;
  final bool isSold;
  final bool isReserved;

  bool get isInstantRequest => request?.isInstantPaid ?? false;

  static _MapDiscoveryEntry? fromProperty(Property p, {required bool isAr}) {
    final lat = p.latitude;
    final lng = p.longitude;
    if (lat == null || lng == null || lat == 0 || lng == 0) return null;
    final st = p.normalizedStatus;
    final soldLike = st == 'sold' || st == 'completed';
    final reserved = p.effectiveWorkflowStage == ListingWorkflowStage.reserved;
    return _MapDiscoveryEntry(
      key: 'property_${p.id}',
      position: LatLng(lat, lng),
      title: PropertyListingDisplay.displayListingTitle(p, isAr),
      city: PropertyListingDisplay.cityLine(p) == '-'
          ? p.city
          : PropertyListingDisplay.cityLine(p),
      amountLabel: soldLike
          ? (isAr ? 'مبيوع' : 'Sold')
          : _amountLabelForProperty(p, isAr: isAr),
      typeLabel: PropertyListingDisplay.typeLabelForProperty(p, isAr),
      imageUrl: ListingMediaUrls.propertyImageNetworkUrl(
            p,
            Supabase.instance.client,
          ) ??
          '',
      property: p,
      isSold: soldLike,
      isReserved: reserved && !soldLike,
    );
  }

  static _MapDiscoveryEntry? fromRequest(
    MarketPropertyRequestRow r, {
    required bool isAr,
    String? coverPublicUrl,
  }) {
    final lat = r.latitude;
    final lng = r.longitude;
    if (lat == null || lng == null || lat == 0 || lng == 0) return null;
    final cover = (coverPublicUrl ?? '').trim();
    final type = PropertyTypeCatalog.label(r.propertyType, isAr);
    final purpose = r.purpose == 'rent'
        ? (isAr ? 'للإيجار' : 'for rent')
        : (isAr ? 'للشراء' : 'to buy');
    return _MapDiscoveryEntry(
      key: 'request_${r.id}',
      position: LatLng(lat, lng),
      title: PropertyListingDisplay.displayRequestTitle(r, isAr),
      city: r.city,
      amountLabel: _budget(r),
      typeLabel: [type, purpose].where((s) => s.trim().isNotEmpty).join(' '),
      imageUrl: cover,
      request: r,
    );
  }

  String mapMarkerPriceLine({required bool isAr}) {
    if (amountLabel.trim().isNotEmpty) return amountLabel;
    if (request != null) {
      return isAr ? 'بدون حدّ للمبلغ المحدد' : 'No amount limit';
    }
    return isAr ? 'السعر عند التواصل' : 'Price on request';
  }

  /// سطر العنوان على الدبوس: نوع + غرض (فيلا للبيع) بدون مدينة مكررة.
  String mapMarkerTitleLine({required bool isAr}) {
    final p = property;
    if (p != null) {
      final type = PropertyListingDisplay.typeLabelForProperty(p, isAr);
      final purpose = PropertyListingDisplay.purposeBitShort(p, isAr);
      final core = [type, purpose].where((s) => s.trim().isNotEmpty).join(' ');
      if (core.isNotEmpty) return _ellipsis(core, isAr ? 26 : 32);
    }
    final r = request;
    if (r != null) {
      final type = PropertyTypeCatalog.label(r.propertyType, isAr);
      final purpose = r.purpose == 'rent'
          ? (isAr ? 'للإيجار' : 'for rent')
          : (isAr ? 'للشراء' : 'to buy');
      final core = [
        if (isAr) 'مطلوب',
        type,
        purpose,
      ].where((s) => s.trim().isNotEmpty).join(' ');
      if (core.isNotEmpty) return _ellipsis(core, isAr ? 26 : 32);
    }
    var t = typeLabel.trim();
    if (t.isEmpty) {
      t = request != null
          ? (isAr ? 'طلب عقاري' : 'Market request')
          : (isAr ? 'إعلان عقاري' : 'Listing');
    }
    return _ellipsis(t, isAr ? 26 : 32);
  }

  /// المدينة + المساحة تحت العنوان (السعر في السطر العلوي).
  String mapMarkerPlaceLine({required bool isAr}) {
    final parts = <String>[];
    final seen = <String>{};

    void addPart(String? raw) {
      final s = (raw ?? '').trim();
      if (s.isEmpty || s == '-') return;
      final key = s.toLowerCase();
      if (seen.contains(key)) return;
      seen.add(key);
      parts.add(s);
    }

    final p = property;
    if (p != null) {
      addPart(PropertyListingDisplay.cityLine(p));
      if (p.area > 0) {
        final a = _compact(p.area);
        addPart(isAr ? '$a م²' : '$a m²');
      }
    } else if (request != null) {
      addPart(city);
      final amin = request!.areaMinM2;
      if (amin != null && amin > 0) {
        final a = _compact(amin);
        addPart(isAr ? 'من $a م²' : 'from $a m²');
      }
    } else {
      addPart(city);
    }

    if (parts.isEmpty) {
      return isAr ? 'موقع على الخريطة' : 'Map location';
    }
    return _ellipsis(parts.join(' · '), isAr ? 34 : 42);
  }

  static String _ellipsis(String text, int maxChars) {
    final ch = Characters(text);
    if (ch.length <= maxChars) return text;
    return '${ch.take(maxChars).string}…';
  }

  String infoSnippet({required bool isAr}) {
    return [
      mapMarkerPriceLine(isAr: isAr),
      title,
      mapMarkerPlaceLine(isAr: isAr),
    ].where((s) => s.trim().isNotEmpty).join(' · ');
  }

  /// سعر/مزاد، وإلا مساحة بم² — بدل رمز عملة فارغ على الدبوس.
  static String _amountLabelForProperty(Property p, {required bool isAr}) {
    var value = p.price;
    if (p.isAuction) {
      final c = p.currentBid;
      if (c != null && c > 0) value = c;
    }
    final m = _money(value, p.currency);
    if (m.isNotEmpty) return m;
    if (p.area > 0) {
      final u = isAr ? 'م²' : 'm²';
      return '${_compact(p.area)} $u';
    }
    return '';
  }

  static String _money(double v, String currency) {
    if (v <= 0) return '';
    final n = _compact(v);
    final cur =
        currency.trim().toUpperCase() == 'SAR' || currency.trim().isEmpty
            ? AppMoney.saudiRiyalSignUnicode
            : currency.trim().toUpperCase();
    return '$n $cur';
  }

  static String _budget(MarketPropertyRequestRow r) {
    final min = r.budgetMin ?? 0;
    final max = r.budgetMax ?? 0;
    if (min > 0 && max > 0) {
      return '${_compact(min)}-${_compact(max)} ${AppMoney.saudiRiyalSignUnicode}';
    }
    if (max > 0) return '${_compact(max)} ${AppMoney.saudiRiyalSignUnicode}';
    if (min > 0) return '${_compact(min)} ${AppMoney.saudiRiyalSignUnicode}+';
    return '';
  }

  static String _compact(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(value >= 10000000 ? 0 : 1)}م';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value >= 100000 ? 0 : 1)}ك';
    }
    return value.toStringAsFixed(0);
  }
}

class _MapDiscoveryCard extends StatelessWidget {
  const _MapDiscoveryCard({
    required this.entry,
    required this.isAr,
    required this.colorScheme,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onDismiss,
    required this.onOpenExternal,
    required this.onOpenDetails,
    required this.hasDetailsAction,
  });

  final _MapDiscoveryEntry entry;
  final bool isAr;
  final ColorScheme colorScheme;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final VoidCallback onDismiss;
  final VoidCallback onOpenExternal;
  final VoidCallback onOpenDetails;
  final bool hasDetailsAction;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 720;
    final imageSize = isCompact ? 96.0 : 132.0;
    final isRequest = entry.request != null;

    // ضغط على البطاقة (الصورة/البيانات/العنوان) يفتح التفاصيل الكاملة فوراً —
    // كأنّ المستخدم ضغط على بطاقة الإعلان في الرئيسية مباشرة. لا نَحجب هذا
    // السلوك إلا في حالة عدم وجود إجراء تفاصيل (مثلاً لو أُعيد استخدام
    // الويدجت من سياق لا يُمرّر `onOpenProperty`/`onOpenRequest`).
    final openDetailsTap = hasDetailsAction ? onOpenDetails : null;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: isCompact ? double.infinity : 640,
      ),
      child: Material(
        elevation: 18,
        shadowColor: Colors.black54,
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // شريط علوي: زر طي/فتح على الحافة، عنوان قابل للضغط لفتح التفاصيل،
            // ثم زر إغلاق. الفصل بين أهداف اللمس يضمن عدم تعارض الإيماءات.
            Row(
              children: [
                IconButton(
                  tooltip: collapsed
                      ? (isAr ? 'توسيع' : 'Expand')
                      : (isAr ? 'طي' : 'Collapse'),
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggleCollapse,
                  icon: Icon(
                    collapsed
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: openDetailsTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          if (entry.isInstantRequest) ...[
                            InstantMarketRequestBadge(isAr: isAr, compact: true),
                            const SizedBox(width: 6),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            margin: const EdgeInsetsDirectional.only(end: 6),
                            decoration: BoxDecoration(
                              color: (isRequest
                                      ? (entry.isInstantRequest
                                          ? const Color(0xFFDC2626)
                                          : const Color(0xFF7C3AED))
                                      : colorScheme.primary)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              isRequest
                                  ? (entry.isInstantRequest
                                      ? (isAr ? 'فوري' : 'Instant')
                                      : (isAr ? 'طلب' : 'Request'))
                                  : (isAr ? 'إعلان' : 'Listing'),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                color: isRequest
                                    ? const Color(0xFF7C3AED)
                                    : colorScheme.primary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              entry.title.trim().isEmpty
                                  ? (isRequest
                                      ? (isAr
                                          ? 'طلب عقاري'
                                          : 'Market request')
                                      : (isAr ? 'إعلان عقاري' : 'Listing'))
                                  : entry.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14.5,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: isAr ? 'إغلاق' : 'Close',
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            if (!collapsed)
              InkWell(
                onTap: openDetailsTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // الصورة على «اليمين للمستخدم» في العربية وعلى «اليسار» في
                      // الإنجليزية بحكم Directionality الأبوي.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          width: imageSize,
                          height: imageSize,
                          child: entry.imageUrl.trim().isNotEmpty
                              ? Image.network(
                                  entry.imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: BrandingLogoImage(
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: BrandingLogoImage(
                                    fit: BoxFit.contain,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              [
                                if (entry.city.trim().isNotEmpty &&
                                    !entry.title
                                        .toLowerCase()
                                        .contains(entry.city.trim().toLowerCase()) &&
                                    !entry.title.contains(
                                        PropertyListingDisplay.placeWithBi(
                                            entry.city.trim())))
                                  entry.city.trim(),
                                if (entry.property != null &&
                                    entry.property!.area > 0)
                                  (isAr
                                      ? '${entry.property!.area.toStringAsFixed(0)} م²'
                                      : '${entry.property!.area.toStringAsFixed(0)} m²'),
                              ].where((e) => e.trim().isNotEmpty).join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                            if (entry.amountLabel.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                entry.amountLabel,
                                style: TextStyle(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final narrow = constraints.maxWidth < 340;
                                return Row(
                                  children: [
                                    if (hasDetailsAction) ...[
                                      Expanded(
                                        child: FilledButton.tonalIcon(
                                          onPressed: onOpenDetails,
                                          icon: const Icon(
                                            Icons.open_in_new,
                                            size: 18,
                                          ),
                                          label: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              isAr ? 'التفاصيل' : 'Details',
                                              maxLines: 1,
                                              softWrap: false,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: narrow ? 6 : 8),
                                    ],
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: onOpenExternal,
                                        icon: const Icon(
                                          Icons.near_me_outlined,
                                          size: 18,
                                        ),
                                        label: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            isAr
                                                ? (narrow
                                                    ? 'خرائط'
                                                    : 'خرائط Google')
                                                : (narrow
                                                    ? 'Maps'
                                                    : 'Google Maps'),
                                            maxLines: 1,
                                            softWrap: false,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
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
}

/// قائمة مدمجة لاختيار نوع الخريطة (عادي/قمري/تضاريس/هجين). تظهر كزرّ
/// شبه شفاف لا يحجب التحكّمات، مع PopupMenu يحفظ المساحة على الشاشات الصغيرة.
class _MapTypeToggle extends StatelessWidget {
  const _MapTypeToggle({
    required this.isAr,
    required this.value,
    required this.onChanged,
  });

  final bool isAr;
  final MapType value;
  final ValueChanged<MapType> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      color: cs.surface.withValues(alpha: 0.92),
      child: PopupMenuButton<MapType>(
        tooltip: isAr ? 'نوع الخريطة' : 'Map type',
        position: PopupMenuPosition.over,
        initialValue: value,
        onSelected: onChanged,
        itemBuilder: (context) => [
          PopupMenuItem(
            value: MapType.normal,
            child: _typeRow(
              context,
              isAr ? 'عاديّة' : 'Normal',
              Icons.map_outlined,
              MapType.normal,
            ),
          ),
          PopupMenuItem(
            value: MapType.satellite,
            child: _typeRow(
              context,
              isAr ? 'قمر صناعي' : 'Satellite',
              Icons.satellite_alt_outlined,
              MapType.satellite,
            ),
          ),
          PopupMenuItem(
            value: MapType.terrain,
            child: _typeRow(
              context,
              isAr ? 'تضاريس' : 'Terrain',
              Icons.terrain_outlined,
              MapType.terrain,
            ),
          ),
          PopupMenuItem(
            value: MapType.hybrid,
            child: _typeRow(
              context,
              isAr ? 'هجين' : 'Hybrid',
              Icons.layers_outlined,
              MapType.hybrid,
            ),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconFor(value), size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                _labelFor(value, isAr),
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeRow(
    BuildContext context,
    String label,
    IconData icon,
    MapType type,
  ) {
    final cs = Theme.of(context).colorScheme;
    final selected = type == value;
    return Row(
      children: [
        Icon(icon, size: 18, color: selected ? cs.primary : cs.onSurface),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: selected ? cs.primary : cs.onSurface,
            ),
          ),
        ),
        if (selected)
          Icon(Icons.check_rounded, size: 18, color: cs.primary),
      ],
    );
  }

  IconData _iconFor(MapType t) {
    switch (t) {
      case MapType.satellite:
        return Icons.satellite_alt_outlined;
      case MapType.terrain:
        return Icons.terrain_outlined;
      case MapType.hybrid:
        return Icons.layers_outlined;
      case MapType.normal:
      case MapType.none:
        return Icons.map_outlined;
    }
  }

  String _labelFor(MapType t, bool isAr) {
    switch (t) {
      case MapType.satellite:
        return isAr ? 'قمر' : 'Satellite';
      case MapType.terrain:
        return isAr ? 'تضاريس' : 'Terrain';
      case MapType.hybrid:
        return isAr ? 'هجين' : 'Hybrid';
      case MapType.normal:
      case MapType.none:
        return isAr ? 'عاديّة' : 'Normal';
    }
  }
}

class _EmptyMapState extends StatelessWidget {
  const _EmptyMapState({required this.isAr});
  final bool isAr;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 56, color: cs.primary),
            const SizedBox(height: 12),
            Text(
              isAr
                  ? 'لا توجد إعلانات أو طلبات بإحداثيات حالياً'
                  : 'No listings or requests with coordinates yet',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

String staticMapUrlForPosition({
  required double lat,
  required double lng,
  int width = 640,
  int height = 360,
  int zoom = 15,
}) {
  final key = Uri.encodeComponent(AppConfig.googleMapsWebBrowserKey);
  // لون هوية موثوق + إخفاء نقاط الاهتمام لخريطة أنظف.
  const style = '&style=feature:poi%7Cvisibility:off'
      '&style=feature:transit%7Cvisibility:off'
      '&style=feature:road%7Celement:geometry%7Ccolor:0xffffff'
      '&style=feature:water%7Celement:geometry%7Ccolor:0xc9e4f0'
      '&style=feature:landscape%7Celement:geometry%7Ccolor:0xf2f7f5';
  return 'https://maps.googleapis.com/maps/api/staticmap'
      '?center=$lat,$lng&zoom=$zoom&size=${width}x$height&scale=2'
      '&maptype=roadmap'
      '$style'
      '&markers=color:0x0B4D3E%7Csize:mid%7C$lat,$lng'
      '&key=$key';
}
