import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/app_config.dart';
import '../core/listing/property_type_catalog.dart';
import '../core/location/map_picker_geolocation.dart';
import '../core/utils/app_money.dart';
import '../models/market_property_request_row.dart';
import '../models/property.dart';

enum MapDiscoveryKind { all, listings, requests }

class PropertyMapDiscoveryPage extends StatefulWidget {
  const PropertyMapDiscoveryPage({
    super.key,
    required this.isAr,
    this.properties = const <Property>[],
    this.requests = const <MarketPropertyRequestRow>[],
    this.focusProperty,
    this.focusRequest,
    this.onOpenProperty,
    this.onOpenRequest,
  });

  final bool isAr;
  final List<Property> properties;
  final List<MarketPropertyRequestRow> requests;
  final Property? focusProperty;
  final MarketPropertyRequestRow? focusRequest;
  final ValueChanged<Property>? onOpenProperty;
  final ValueChanged<MarketPropertyRequestRow>? onOpenRequest;

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

  bool get _isAr => widget.isAr;

  @override
  void initState() {
    super.initState();
    _selected = _initialSelection();
    unawaited(_rebuildMarkers());
  }

  @override
  void didUpdateWidget(covariant PropertyMapDiscoveryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.properties != widget.properties ||
        oldWidget.requests != widget.requests ||
        oldWidget.focusProperty != widget.focusProperty ||
        oldWidget.focusRequest != widget.focusRequest) {
      _selected ??= _initialSelection();
      unawaited(_rebuildMarkers());
    }
  }

  List<_MapDiscoveryEntry> get _allEntries {
    return <_MapDiscoveryEntry>[
      ...widget.properties
          .map((p) => _MapDiscoveryEntry.fromProperty(p, isAr: _isAr))
          .whereType<_MapDiscoveryEntry>(),
      ...widget.requests
          .map((r) => _MapDiscoveryEntry.fromRequest(r, isAr: _isAr))
          .whereType<_MapDiscoveryEntry>(),
    ];
  }

  List<_MapDiscoveryEntry> get _visibleEntries {
    final all = _allEntries;
    return all.where((e) {
      return switch (_kind) {
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
    if (fr != null) return _MapDiscoveryEntry.fromRequest(fr, isAr: _isAr);
    return _allEntries.firstOrNull;
  }

  LatLng get _initialTarget => _selected?.position ?? _saudiCenter;

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
            e.markerLabel(isAr: _isAr),
            isRequest: e.request != null,
            selected: selected,
          ),
          anchor: const Offset(0.5, 0.82),
          onTap: () {
            unawaited(_focusEntry(e));
          },
          infoWindow: InfoWindow(
            title: e.markerLabel(isAr: _isAr),
            snippet: e.infoSnippet(isAr: _isAr),
            onTap: () => _openSelectedDetails(e),
          ),
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _markers = markers;
      _buildingMarkers = false;
    });
  }

  Future<void> _focusEntry(_MapDiscoveryEntry e, {double zoom = 15.25}) async {
    setState(() => _selected = e);
    try {
      await _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(e.position, zoom),
      );
      await _controller?.showMarkerInfoWindow(MarkerId(e.key));
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

  Future<BitmapDescriptor> _priceMarkerIcon(
    String label, {
    required bool isRequest,
    required bool selected,
  }) async {
    final text = label.trim().isEmpty ? (_isAr ? 'عقار' : 'Listing') : label;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: selected ? 34 : 30,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = math.max(112.0, painter.width + 42);
    final height = selected ? 70.0 : 62.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height - 10),
      const Radius.circular(28),
    );
    final color = isRequest ? const Color(0xFF7C3AED) : const Color(0xFF0F766E);
    canvas.drawRRect(rect, Paint()..color = color);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 5 : 3
        ..color = Colors.white,
    );
    final path = Path()
      ..moveTo(width / 2 - 10, height - 11)
      ..lineTo(width / 2, height)
      ..lineTo(width / 2 + 10, height - 11)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    painter.paint(canvas, Offset((width - painter.width) / 2, 12));
    final image =
        await recorder.endRecording().toImage(width.ceil(), height.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  void _setKind(MapDiscoveryKind kind) {
    setState(() {
      _kind = kind;
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

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isAr ? 'خريطة العقارات' : 'Property map'),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: entries.isEmpty
                  ? _EmptyMapState(isAr: _isAr)
                  : GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _initialTarget,
                        zoom: _selected == null ? 5.2 : 13.5,
                      ),
                      markers: _markers,
                      onMapCreated: (c) {
                        _controller = c;
                        final target = _selected?.position;
                        if (target != null) {
                          unawaited(c.animateCamera(
                            CameraUpdate.newLatLngZoom(target, 13.5),
                          ));
                          unawaited(c.showMarkerInfoWindow(
                            MarkerId(_selected!.key),
                          ));
                        }
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
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: MapDiscoveryKind.values.map((kind) {
                    final selected = _kind == kind;
                    return ChoiceChip(
                      selected: selected,
                      label: Text(_kindLabel(kind)),
                      avatar: Icon(
                        kind == MapDiscoveryKind.requests
                            ? Icons.request_quote_outlined
                            : kind == MapDiscoveryKind.listings
                                ? Icons.apartment_outlined
                                : Icons.layers_outlined,
                        size: 18,
                      ),
                      onSelected: (_) => _setKind(kind),
                    );
                  }).toList(),
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
            PositionedDirectional(
              end: 12,
              bottom: (_selected == null ? 16 : 150) +
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
                  onOpenExternal: () => _openExternal(_selected!),
                  onFocus: () => _focusEntry(_selected!, zoom: 17),
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

  static _MapDiscoveryEntry? fromProperty(Property p, {required bool isAr}) {
    final lat = p.latitude;
    final lng = p.longitude;
    if (lat == null || lng == null || lat == 0 || lng == 0) return null;
    return _MapDiscoveryEntry(
      key: 'property_${p.id}',
      position: LatLng(lat, lng),
      title: p.title,
      city: p.city,
      amountLabel: _money(p.price, p.currency),
      typeLabel: PropertyTypeCatalog.label(
        p.listingTypeKey.trim().isNotEmpty ? p.listingTypeKey : p.type.name,
        isAr,
      ),
      imageUrl: p.images.isNotEmpty ? p.images.first : '',
      property: p,
    );
  }

  static _MapDiscoveryEntry? fromRequest(
    MarketPropertyRequestRow r, {
    required bool isAr,
  }) {
    final lat = r.latitude;
    final lng = r.longitude;
    if (lat == null || lng == null || lat == 0 || lng == 0) return null;
    return _MapDiscoveryEntry(
      key: 'request_${r.id}',
      position: LatLng(lat, lng),
      title: r.title,
      city: r.city,
      amountLabel: _budget(r),
      typeLabel: r.purpose == 'rent'
          ? (isAr ? 'طلب إيجار' : 'Rent request')
          : (isAr ? 'طلب شراء' : 'Purchase request'),
      imageUrl: '',
      request: r,
    );
  }

  String markerLabel({required bool isAr}) {
    if (amountLabel.trim().isNotEmpty) return amountLabel;
    return request != null ? (isAr ? 'طلب' : 'Req') : (isAr ? 'عقار' : 'Ad');
  }

  String infoSnippet({required bool isAr}) {
    return [
      title,
      city,
      typeLabel,
    ].where((s) => s.trim().isNotEmpty).join(' - ');
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
    required this.onOpenExternal,
    required this.onFocus,
    required this.onOpenDetails,
    required this.hasDetailsAction,
  });

  final _MapDiscoveryEntry entry;
  final bool isAr;
  final ColorScheme colorScheme;
  final VoidCallback onOpenExternal;
  final VoidCallback onFocus;
  final VoidCallback onOpenDetails;
  final bool hasDetailsAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 14,
      shadowColor: Colors.black38,
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onFocus,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 92,
                  height: 82,
                  child: entry.imageUrl.isNotEmpty
                      ? Image.network(entry.imageUrl, fit: BoxFit.cover)
                      : ColoredBox(
                          color: colorScheme.primaryContainer,
                          child: Icon(
                            entry.request != null
                                ? Icons.request_quote_outlined
                                : Icons.apartment_outlined,
                            color: colorScheme.onPrimaryContainer,
                            size: 34,
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
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [
                        entry.city,
                        entry.typeLabel,
                      ].where((e) => e.trim().isNotEmpty).join(' - '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    if (entry.amountLabel.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        entry.amountLabel,
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (hasDetailsAction)
                          FilledButton.tonalIcon(
                            onPressed: onOpenDetails,
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: Text(isAr ? 'فتح التفاصيل' : 'Details'),
                          ),
                        OutlinedButton.icon(
                          onPressed: onOpenExternal,
                          icon: const Icon(Icons.near_me_outlined, size: 18),
                          label: Text(isAr ? 'خرائط Google' : 'Google Maps'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
  return 'https://maps.googleapis.com/maps/api/staticmap'
      '?center=$lat,$lng&zoom=$zoom&size=${width}x$height&scale=2'
      '&maptype=roadmap&markers=color:red%7C$lat,$lng&key=$key';
}
