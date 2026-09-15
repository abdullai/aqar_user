import 'dart:async';

import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:aqar_user/l10n/app_localizations.dart';

import '../core/location/map_picker_geolocation.dart';
import '../core/location/map_engine_hint.dart';
import '../core/navigation/safe_overlay_pop.dart';
import '../core/navigation/web_in_app_nav.dart';
import '../widgets/app_page_close_button.dart';
import '../core/permissions/runtime_permission_helper.dart';
import '../services/saudi_districts_service.dart';
import '../services/saudi_locations_service.dart';
import '../widgets/app_logo_loading.dart';

class MapPickerPage extends StatefulWidget {
  final LatLng? initial;
  final bool isAr;
  final String? pinTitle;
  final String? pinSubtitle;
  final String? pinAmountLabel;
  final String? pinKindLabel;

  /// عرض المملكة بالكامل عند فتح الخريطة بدون نقطة محددة مسبقاً
  final bool kingdomOverview;

  const MapPickerPage({
    super.key,
    this.initial,
    this.isAr = true,
    this.kingdomOverview = false,
    this.pinTitle,
    this.pinSubtitle,
    this.pinAmountLabel,
    this.pinKindLabel,
  });

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  static const LatLng _riyadh = LatLng(24.7136, 46.6753);

  /// مركز تقريبي للمملكة لعرض الخريطة بزوم واسع
  static const LatLng _saudiCenter = LatLng(23.993165, 45.078064);

  GoogleMapController? _controller;
  final GlobalKey _mapLayerKey = GlobalKey();
  late final CameraPosition _bootCamera;

  late LatLng _selected;
  late double _mapZoom;

  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;

  bool _loading = true;
  bool _mapReady = false;
  bool _locatingNow = false;

  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _saLocations = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _results = <Map<String, dynamic>>[];

  String? _locationHint;

  /// بيانات مكان من البحث (مدينة/حي) — تُعاد مع التأكيد لملء النموذج بدقة.
  String? _pickedCity;
  String? _pickedRegion;
  String? _pickedGovernorate;
  String? _pickedDistrict;

  /// أندرويد: هواوي/هونر بدون GMS — نفضّل مسار Petal Maps الخارجي.
  MapEngineHint _mapEngineHint = MapEngineHint.googleMaps;

  /// أندرويد: إن لم يُستدعَ [GoogleMap.onMapCreated] خلال مهلة، نفترض تعطيل/بطء GMS أو WebView.
  bool _mapLoadStalled = false;
  Timer? _mapStallTimer;

  String get _pinTitle {
    final amount = (widget.pinAmountLabel ?? '').trim();
    if (amount.isNotEmpty) return amount;
    final title = (widget.pinTitle ?? '').trim();
    if (title.isNotEmpty) return title;
    return widget.isAr ? 'الموقع المحدد' : 'Selected location';
  }

  String get _pinSubtitle {
    final parts = <String>[
      (widget.pinKindLabel ?? '').trim(),
      (widget.pinTitle ?? '').trim(),
      (widget.pinSubtitle ?? '').trim(),
    ].where((s) => s.isNotEmpty && s != _pinTitle).toList(growable: false);
    if (parts.isNotEmpty) {
      return parts.take(3).join(' · ');
    }
    return widget.isAr
        ? 'حرّك الخريطة حتى يثبت الدبوس في المنتصف على الموقع الدقيق'
        : 'Move the map so the center pin sits on the exact spot';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_resolveMapEngineHint());
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _mapStallTimer = Timer(const Duration(seconds: 14), () {
        if (!mounted || _mapReady) return;
        setState(() => _mapLoadStalled = true);
      });
    }
    final useKingdom = widget.kingdomOverview && widget.initial == null;
    _mapZoom = useKingdom ? 5.85 : 13.0;
    _selected = widget.initial ?? (useKingdom ? _saudiCenter : _riyadh);
    _bootCamera = CameraPosition(target: _selected, zoom: _mapZoom);
    _latCtrl = TextEditingController(
      text: _selected.latitude.toStringAsFixed(6),
    );
    _lngCtrl = TextEditingController(
      text: _selected.longitude.toStringAsFixed(6),
    );
    _init();
    WebInAppNav.holdBack();
  }

  Future<void> _resolveMapEngineHint() async {
    try {
      final h = await MapEngineHintResolver.resolve();
      if (!mounted) return;
      setState(() => _mapEngineHint = h);
    } catch (_) {}
  }

  Future<void> _openExternalMapsAtSelection() async {
    final lat = _selected.latitude;
    final lng = _selected.longitude;
    final candidates = <Uri>[
      Uri.parse('petalmaps://map?lat=$lat&lng=$lng'),
      Uri.parse('https://www.petalmaps.com/place/$lat,$lng'),
      Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
    ];
    for (final u in candidates) {
      try {
        if (await canLaunchUrl(u)) {
          await launchUrl(u, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
    }
  }

  Future<void> _init() async {
    // لا نُجمّد فتح الخريطة ببناء فهرس المدن/الأحياء — يُحمَّل في الخلفية.
    unawaited(_loadSaudiLocations());
    // نقطة ممرَّرة مسبقاً: لا تستبدلها بـ GPS (يحرّك الدبوس بعيداً عن الاختيار).
    if (widget.initial != null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _locationHint = widget.isAr
              ? 'الموقع المحدد. يمكنك السحب أو البحث أو زر موقعي الحالي.'
              : 'Pinned location. Drag, search, or use current location.';
        });
      }
      return;
    }
    if (widget.kingdomOverview) {
      if (mounted) {
        setState(() {
          _loading = false;
          _locationHint = widget.isAr
              ? 'اختر النقطة على خريطة المملكة، أو ابحث باسم المدينة.'
              : 'Pick a point on the map of the Kingdom, or search by city.';
        });
      }
      return;
    }
    await _detectLocation(useFallbackIfFail: true);
  }

  @override
  void dispose() {
    _mapStallTimer?.cancel();
    _searchCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    // لا تستدعِ dispose على [GoogleMapController]: عنصر [GoogleMap] يتولى ذلك.
    // استدعاء مزدوج يسبب أعطالاً عند اللمس (خروج/انهيار) خصوصاً على أندرويد.
    _controller = null;
    scheduleMicrotask(WebInAppNav.releaseBack);
    super.dispose();
  }

  /// تحريك برمجي للكاميرا — لا نُحدّث الحقول من onCameraIdle أثناءه مرتين بلا داعٍ.
  bool _programmaticCamera = false;
  LatLng? _lastMoveTarget;
  DateTime? _ignoreIdleUntil;

  void _setSelected(LatLng pos, {bool syncFields = true}) {
    _selected = pos;
    if (!syncFields) return;
    _latCtrl.text = _selected.latitude.toStringAsFixed(6);
    _lngCtrl.text = _selected.longitude.toStringAsFixed(6);
  }

  Future<void> _loadSaudiLocations() async {
    try {
      final cities = await SaudiLocationsService.instance.loadAll();
      final districtsMap =
          await SaudiDistrictsService.instance.loadMergedWithCityAliases();
      final out = <Map<String, dynamic>>[];
      for (final c in cities) {
        final city = widget.isAr ? c.cityAr.trim() : c.cityEn.trim();
        final region = widget.isAr ? c.regionAr.trim() : c.regionEn.trim();
        final gov = widget.isAr
            ? (c.governorateAr?.trim() ?? '')
            : (c.governorateEn?.trim() ?? '');
        if (city.isEmpty || c.lat == 0 && c.lng == 0) continue;
        out.add({
          'city': city,
          'region': region,
          'governorate': gov.isNotEmpty ? gov : city,
          'district': '',
          'lat': c.lat,
          'lng': c.lng,
        });
        final districts = districtsMap[city] ??
            districtsMap[c.cityAr] ??
            districtsMap[c.cityEn] ??
            const <String>[];
        for (final d in districts.take(24)) {
          out.add({
            'city': city,
            'region': region,
            'governorate': gov.isNotEmpty ? gov : city,
            'district': d,
            'lat': c.lat,
            'lng': c.lng,
          });
        }
      }
      _saLocations = out;
    } catch (e) {
      if (kDebugMode) {
        print('[DBG][MAP] saudi_locations load failed: $e');
      }
    }
  }

  Future<void> _detectLocation({bool useFallbackIfFail = false}) async {
    if (_locatingNow) return;

    _locatingNow = true;

    if (mounted) {
      setState(() {
        _loading = true;
        _locationHint = null;
      });
    }

    try {
      final outcome = await detectMapPickerLocation(isWeb: kIsWeb);

      switch (outcome.status) {
        case MapPickerLocateStatus.serviceDisabled:
          if (useFallbackIfFail) {
            await _moveToLocation(
              _selected.latitude == 0 && _selected.longitude == 0
                  ? _riyadh
                  : _selected,
              zoom: _mapZoom,
            );
          }
          if (mounted) {
            setState(() {
              _loading = false;
              _locationHint = widget.isAr
                  ? 'خدمة الموقع غير مفعلة. يمكنك اختيار الموقع يدويًا من الخريطة.'
                  : 'Location service is disabled. You can select the location manually on the map.';
            });
          }
          return;
        case MapPickerLocateStatus.permissionDenied:
          if (useFallbackIfFail) {
            await _moveToLocation(
              widget.initial ?? _riyadh,
              zoom: _mapZoom,
            );
          }
          if (mounted) {
            setState(() {
              _loading = false;
              _locationHint = widget.isAr
                  ? 'لم يتم منح إذن الموقع. يمكنك اختيار الموقع يدويًا.'
                  : 'Location permission was not granted. You can pick the location manually.';
            });
          }
          return;
        case MapPickerLocateStatus.ok:
          final latlng = outcome.position;
          if (latlng == null) return;
          if (!mounted) return;
          setState(() {
            _setSelected(latlng);
            _pickedCity = null;
            _pickedRegion = null;
            _pickedGovernorate = null;
            _pickedDistrict = null;
            _loading = false;
            _locationHint = widget.isAr
                ? 'تم جلب الموقع الحالي بدقة. على الويب قد تكون تقريبية — عدّل الدبوس إن لزم.'
                : 'Current location set. On web it may be approximate — adjust the pin if needed.';
          });
          await _moveToLocation(latlng, zoom: 17);
          return;
        case MapPickerLocateStatus.failed:
          break;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DBG][MAP] detect location failed: $e');
      }

      if (useFallbackIfFail) {
        await _moveToLocation(widget.initial ?? _riyadh, zoom: _mapZoom);
      }

      if (mounted) {
        setState(() {
          _loading = false;
          _locationHint = widget.isAr
              ? 'تعذر تحديد الموقع بدقة. اختر الموقع يدويًا من الخريطة أو ابحث باسم المدينة.'
              : 'Could not determine the exact location. Select it manually on the map or search by city.';
        });
      }
    } finally {
      _locatingNow = false;
    }
  }

  Future<void> _moveCamera(CameraUpdate update) async {
    final c = _controller;
    if (c == null || !_mapReady) return;
    _programmaticCamera = true;
    _ignoreIdleUntil = DateTime.now().add(const Duration(milliseconds: 900));
    try {
      if (kIsWeb) {
        await c.moveCamera(update).timeout(const Duration(seconds: 4));
      } else {
        await c.animateCamera(update).timeout(const Duration(seconds: 8));
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DBG][MAP] camera move failed: $e');
      }
    } finally {
      _programmaticCamera = false;
    }
  }

  Future<void> _moveToLocation(LatLng pos, {double zoom = 15}) async {
    if (!mounted) return;

    setState(() {
      _setSelected(pos);
      _lastMoveTarget = pos;
    });

    if (_mapReady && _controller != null) {
      await _moveCamera(CameraUpdate.newLatLngZoom(pos, zoom));
    }
  }

  void _onTap(LatLng pos) {
    setState(() {
      _setSelected(pos);
      _lastMoveTarget = pos;
      // النقر اليدوي يلغي بيانات البحث السابقة — يُملأ النموذج من أقرب مدينة.
      _pickedCity = null;
      _pickedRegion = null;
      _pickedGovernorate = null;
      _pickedDistrict = null;
    });
    unawaited(_focusSelectedMarker());
  }

  Future<void> _focusSelectedMarker() async {
    if (_controller == null || !_mapReady) return;
    // على الويب: لا تُحرّك الزوم إلى 17 عند كل نقرة — animateCamera يجمد Safari.
    if (kIsWeb) {
      await _moveCamera(CameraUpdate.newLatLng(_selected));
      return;
    }
    await _moveCamera(CameraUpdate.newLatLngZoom(_selected, 17));
  }

  void _onCameraMove(CameraPosition pos) {
    _lastMoveTarget = pos.target;
    _mapZoom = pos.zoom;
  }

  bool _approximateLocation = false;

  bool _submitted = false;

  void _confirm() {
    _submitPickedLocation(approximate: _approximateLocation);
  }

  void _submitPickedLocation({required bool approximate}) {
    if (_submitted || !mounted) return;
    _submitted = true;
    final result = <String, dynamic>{
      'lat': _selected.latitude,
      'lng': _selected.longitude,
      'approximate': approximate,
      if ((_pickedCity ?? '').trim().isNotEmpty) 'city': _pickedCity!.trim(),
      if ((_pickedRegion ?? '').trim().isNotEmpty)
        'region': _pickedRegion!.trim(),
      if ((_pickedGovernorate ?? '').trim().isNotEmpty)
        'governorate': _pickedGovernorate!.trim(),
      if ((_pickedDistrict ?? '').trim().isNotEmpty)
        'district': _pickedDistrict!.trim(),
    };
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) {
      _submitted = false;
      return;
    }
    Navigator.of(context).pop(result);
  }

  /// بديل عند فشل الخريطة المضمّنة (هواوي/هونر بدون GMS أو تعطيل WebGL).
  Future<void> _openInExternalMaps() async {
    final q =
        '${_selected.latitude.toStringAsFixed(6)},${_selected.longitude.toStringAsFixed(6)}';
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}',
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _search(String q) {
    final query = q.trim().toLowerCase();

    if (query.isEmpty) {
      setState(() => _results = <Map<String, dynamic>>[]);
      return;
    }

    final results = _saLocations
        .where((e) {
          final city = (e['city'] ?? '').toString().toLowerCase();
          final region = (e['region'] ?? '').toString().toLowerCase();
          final district = (e['district'] ?? '').toString().toLowerCase();
          return city.contains(query) ||
              region.contains(query) ||
              district.contains(query);
        })
        .take(12)
        .toList();

    setState(() => _results = results);
  }

  Future<void> _selectLocation(Map<String, dynamic> loc) async {
    final latValue = loc['lat'];
    final lngValue = loc['lng'];

    if (latValue == null || lngValue == null) return;

    final lat = (latValue as num).toDouble();
    final lng = (lngValue as num).toDouble();
    final pos = LatLng(lat, lng);
    final city = (loc['city'] ?? '').toString().trim();
    final district = (loc['district'] ?? '').toString().trim();

    setState(() {
      _results.clear();
      _searchCtrl.text = district.isNotEmpty ? '$district — $city' : city;
      _locationHint = null;
      _pickedCity = city.isEmpty ? null : city;
      _pickedRegion = (loc['region'] ?? '').toString().trim();
      if ((_pickedRegion ?? '').isEmpty) _pickedRegion = null;
      _pickedGovernorate = (loc['governorate'] ?? '').toString().trim();
      if ((_pickedGovernorate ?? '').isEmpty) _pickedGovernorate = null;
      _pickedDistrict = district.isEmpty ? null : district;
    });

    await _moveToLocation(pos, zoom: district.isNotEmpty ? 14.5 : 15);
  }

  Future<void> _onGoogleMapCreated(GoogleMapController controller) async {
    _mapStallTimer?.cancel();
    _mapStallTimer = null;
    _controller = controller;
    if (mounted) {
      setState(() {
        _mapReady = true;
        _mapLoadStalled = false;
      });
    } else {
      _mapReady = true;
      _mapLoadStalled = false;
    }
    try {
      await controller.moveCamera(
        CameraUpdate.newLatLngZoom(_selected, _mapZoom),
      );
    } catch (_) {}
  }

  bool _shouldIgnoreCameraIdle() {
    if (_programmaticCamera) return true;
    final until = _ignoreIdleUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void _onCameraIdle() {
    if (!mounted || _shouldIgnoreCameraIdle()) return;
    if (kIsWeb) {
      final t = _lastMoveTarget;
      if (t == null) return;
      if ((t.latitude - _selected.latitude).abs() < 1e-7 &&
          (t.longitude - _selected.longitude).abs() < 1e-7) {
        return;
      }
      setState(() => _setSelected(t));
      return;
    }
    unawaited(_captureMapCenter());
  }

  Future<void> _captureMapCenter() async {
    if (!mounted || _shouldIgnoreCameraIdle() || !_mapReady) return;
    final c = _controller;
    if (c == null) return;
    final box = _mapLayerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    try {
      final ll = await c
          .getLatLng(
            ScreenCoordinate(
              x: (box.size.width / 2).round(),
              y: (box.size.height / 2).round(),
            ),
          )
          .timeout(const Duration(seconds: 2));
      if (!mounted || _shouldIgnoreCameraIdle()) return;
      if ((ll.latitude - _selected.latitude).abs() < 1e-7 &&
          (ll.longitude - _selected.longitude).abs() < 1e-7) {
        return;
      }
      setState(() => _setSelected(ll));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    final t = AppLocalizations.of(context);

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: AppPageCloseButton(
            isArabic: isAr,
            onPressed: () => SafeOverlayPop.pop(context),
          ),
          title: Text(isAr ? 'تحديد الموقع' : 'Select location'),
          actions: [
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: () async {
                if (!kIsWeb &&
                    (defaultTargetPlatform == TargetPlatform.android ||
                        defaultTargetPlatform == TargetPlatform.iOS)) {
                  final loc = AppLocalizations.of(context);
                  if (loc != null) {
                    final ok = await RuntimePermissionHelper.ensureLocation(
                      context,
                      t: loc,
                    );
                    if (!context.mounted) return;
                    if (!ok) return;
                  }
                }
                await _detectLocation(useFallbackIfFail: true);
              },
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _confirm,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  KeyedSubtree(
                    key: _mapLayerKey,
                    child: _LockedGoogleMap(
                      boot: _bootCamera,
                      onCreated: _onGoogleMapCreated,
                      onTap: _onTap,
                      onCameraMove: _onCameraMove,
                      onCameraIdle: _onCameraIdle,
                    ),
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 36),
                        child: Semantics(
                          label: _pinSubtitle,
                          child: Icon(
                            Icons.location_on_rounded,
                            size: 52,
                            color: Theme.of(context).colorScheme.primary,
                            shadows: const [
                              Shadow(
                                blurRadius: 8,
                                color: Color(0x66000000),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: SafeArea(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                        children: [
                          if (_mapEngineHint ==
                                  MapEngineHint.huaweiPetalPreferred &&
                              t != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                elevation: 2,
                                borderRadius: BorderRadius.circular(12),
                                color: Theme.of(context)
                                    .colorScheme
                                    .tertiaryContainer
                                    .withValues(alpha: 0.95),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.info_outline_rounded,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onTertiaryContainer,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              t.mapPickerHuaweiNoGmsBanner,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                height: 1.35,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onTertiaryContainer,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      FilledButton.tonalIcon(
                                        onPressed: _openExternalMapsAtSelection,
                                        icon: const Icon(Icons.map_outlined),
                                        label: Text(
                                          isAr
                                              ? 'فتح في خرائط Petal / بديل'
                                              : 'Open in Petal Maps / fallback',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (_mapLoadStalled && t != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                elevation: 2,
                                borderRadius: BorderRadius.circular(12),
                                color: Theme.of(context)
                                    .colorScheme
                                    .errorContainer
                                    .withValues(alpha: 0.92),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.map_outlined,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onErrorContainer,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          t.mapPickerMapLoadStalledBanner,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            height: 1.35,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onErrorContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(14),
                            child: AqarTextField(
                              controller: _searchCtrl,
                              onChanged: _search,
                              decoration: InputDecoration(
                                hintText: isAr
                                    ? 'ابحث عن الأحياء أو المدن أو المناطق'
                                    : 'Search neighborhoods, cities, or regions',
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                prefixIcon: const Icon(Icons.search),
                              ),
                            ),
                          ),
                          if (_results.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              constraints: const BoxConstraints(maxHeight: 280),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: const [
                                  BoxShadow(
                                    blurRadius: 8,
                                    color: Colors.black12,
                                  ),
                                ],
                              ),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: _results.length,
                                itemBuilder: (_, i) {
                                  final e = _results[i];
                                  return ListTile(
                                    title: Text((e['city'] ?? '').toString()),
                                    subtitle: Text(
                                      [
                                        (e['district'] ?? '').toString(),
                                        (e['region'] ?? '').toString(),
                                      ]
                                          .where((s) => s.trim().isNotEmpty)
                                          .join(' - '),
                                    ),
                                    onTap: () => _selectLocation(e),
                                  );
                                },
                              ),
                            ),
                          if (_locationHint != null &&
                              _locationHint!.trim().isNotEmpty)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _locationHint!,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                        ),
                      ),
                    ),
                  ),
                  if (_loading)
                    Container(
                      color: Colors.black12,
                      child: const Center(
                        child: AppLogoLoading(),
                      ),
                    ),
                ],
              ),
            ),
            Material(
              elevation: 10,
              color: Theme.of(context).colorScheme.surface,
              shadowColor: Colors.black.withValues(alpha: 0.12),
              child: SafeArea(
                top: false,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.my_location_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _pinTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Directionality(
                                      textDirection: TextDirection.ltr,
                                      child: Text(
                                        '${_selected.latitude.toStringAsFixed(6)}, '
                                        '${_selected.longitude.toStringAsFixed(6)}',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _PrecisionCard(
                                  selected: !_approximateLocation,
                                  title: isAr ? 'موقع محدد' : 'Exact',
                                  subtitle: isAr
                                      ? 'يظهر على خريطة الإعلانات'
                                      : 'Shown on the ads map',
                                  onTap: () => setState(
                                    () => _approximateLocation = false,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _PrecisionCard(
                                  selected: _approximateLocation,
                                  title: isAr ? 'موقع تقريبي' : 'Approximate',
                                  subtitle: isAr
                                      ? 'لا يظهر بدقة على الخريطة'
                                      : 'Not shown precisely on the map',
                                  onTap: () => setState(
                                    () => _approximateLocation = true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: FilledButton.icon(
                                  icon: const Icon(Icons.check),
                                  label: Text(
                                    isAr ? 'اعتماد الموقع' : 'Confirm location',
                                  ),
                                  onPressed: _confirm,
                                ),
                              ),
                              if (t != null) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.map_outlined),
                                    label: Text(isAr ? 'خرائط' : 'Maps'),
                                    onPressed: () =>
                                        unawaited(_openInExternalMaps()),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrecisionCard extends StatelessWidget {
  const _PrecisionCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = selected ? cs.primary : cs.outlineVariant;
    final bg = selected
        ? cs.primary.withValues(alpha: 0.12)
        : cs.surfaceContainerHighest.withValues(alpha: 0.35);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 1.6 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: selected ? cs.primary : cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// خريطة لا تُعاد تهيئة كاميرتها عند setState للأب — يمنع قفز الدبوس على الويب.
class _LockedGoogleMap extends StatefulWidget {
  const _LockedGoogleMap({
    required this.boot,
    required this.onCreated,
    required this.onTap,
    required this.onCameraMove,
    required this.onCameraIdle,
  });

  final CameraPosition boot;
  final Future<void> Function(GoogleMapController controller) onCreated;
  final void Function(LatLng pos) onTap;
  final void Function(CameraPosition pos) onCameraMove;
  final VoidCallback onCameraIdle;

  @override
  State<_LockedGoogleMap> createState() => _LockedGoogleMapState();
}

class _LockedGoogleMapState extends State<_LockedGoogleMap> {
  late final CameraPosition _boot = widget.boot;

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: _boot,
      onMapCreated: (c) => unawaited(widget.onCreated(c)),
      markers: const <Marker>{},
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: true,
      mapToolbarEnabled: false,
      compassEnabled: true,
      rotateGesturesEnabled: true,
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      tiltGesturesEnabled: true,
      onTap: widget.onTap,
      onCameraMove: widget.onCameraMove,
      onCameraIdle: widget.onCameraIdle,
    );
  }
}
