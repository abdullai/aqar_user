import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/gestures/app_keyboard_inset.dart';
import '../core/gestures/app_keyboard_stable.dart' show showAppDialog;
import '../core/navigation/web_in_app_nav.dart';
import '../models/national_address_model.dart';
import '../services/national_address_service.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/aqar_text_field.dart';

class NationalAddressPickerScreen extends StatefulWidget {
  static const routeName = '/national-address-picker';

  const NationalAddressPickerScreen({
    super.key,
    required this.isAr,
    this.initialLatitude,
    this.initialLongitude,
    this.kingdomOverview = false,
  });

  final bool isAr;
  final double? initialLatitude;
  final double? initialLongitude;
  final bool kingdomOverview;

  static Future<NationalAddressModel?> pick(
    BuildContext context, {
    required bool isAr,
    double? initialLatitude,
    double? initialLongitude,
    bool kingdomOverview = false,
  }) {
    return Navigator.of(context).push<NationalAddressModel>(
      MaterialPageRoute<NationalAddressModel>(
        fullscreenDialog: true,
        settings: const RouteSettings(name: routeName),
        builder: (_) => NationalAddressPickerScreen(
          isAr: isAr,
          initialLatitude: initialLatitude,
          initialLongitude: initialLongitude,
          kingdomOverview: kingdomOverview,
        ),
      ),
    );
  }

  @override
  State<NationalAddressPickerScreen> createState() =>
      _NationalAddressPickerScreenState();
}

class _NationalAddressPickerScreenState
    extends State<NationalAddressPickerScreen> {
  static const LatLng _saudiCenter = LatLng(23.8859, 45.0792);

  final MapController _mapController = MapController();
  final NationalAddressService _service = NationalAddressService();
  final TextEditingController _searchController = TextEditingController();

  late LatLng _center;
  NationalAddressModel? _selected;
  List<NationalAddressModel> _searchResults = const [];
  Timer? _reverseDebounce;
  int _requestGeneration = 0;
  bool _mapReady = false;
  bool _searching = false;
  bool _loadingAddress = false;
  bool _locating = false;
  String? _error;

  bool get _isAr => widget.isAr;

  @override
  void initState() {
    super.initState();
    final latitude = widget.initialLatitude;
    final longitude = widget.initialLongitude;
    _center = latitude != null &&
            longitude != null &&
            latitude >= -90 &&
            latitude <= 90 &&
            longitude >= -180 &&
            longitude <= 180
        ? LatLng(latitude, longitude)
        : _saudiCenter;
    if (latitude != null && longitude != null) {
      _selected = NationalAddressModel(
        latitude: latitude,
        longitude: longitude,
      );
    }
  }

  @override
  void dispose() {
    _reverseDebounce?.cancel();
    _requestGeneration++;
    _service.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _center = camera.center;
    _selected = NationalAddressModel(
      latitude: _center.latitude,
      longitude: _center.longitude,
    );
    _reverseDebounce?.cancel();
    _requestGeneration++;
    _service.cancelPending();
    _searching = false;
    _loadingAddress = false;
    final generation = _requestGeneration;
    _reverseDebounce = Timer(const Duration(milliseconds: 800), () {
      unawaited(_reverseGeocode(_center, generation));
    });
    if (mounted) setState(() {});
  }

  Future<void> _reverseGeocode(LatLng point, int generation) async {
    if (!NationalAddressService.isWithinSaudiArabia(
      point.latitude,
      point.longitude,
    )) {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _loadingAddress = false;
          _error = _isAr
              ? 'الموقع خارج نطاق تغطية العنوان الوطني.'
              : 'The location is outside National Address coverage.';
        });
      }
      return;
    }

    setState(() {
      _loadingAddress = true;
      _error = null;
    });
    try {
      final results = await _service.reverseGeocode(
        latitude: point.latitude,
        longitude: point.longitude,
      );
      if (!mounted || generation != _requestGeneration || results == null) {
        return;
      }
      setState(() {
        _selected = results.isEmpty
            ? NationalAddressModel(
                latitude: point.latitude,
                longitude: point.longitude,
              )
            : results.first.copyWith(
                latitude: point.latitude,
                longitude: point.longitude,
              );
        _loadingAddress = false;
      });
    } on NationalAddressServiceException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loadingAddress = false;
        _error = error.localized(_isAr);
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loadingAddress = false;
        _error = _isAr
            ? 'تعذر جلب بيانات العنوان. تحقق من الاتصال وحاول مجددًا.'
            : 'Could not load address details. Check your connection and retry.';
      });
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (!NationalAddressService.isValidSearchTerm(query)) {
      setState(() {
        _error = _isAr
            ? 'أدخل الرمز المختصر أو أربعة أحرف على الأقل.'
            : 'Enter a short address or at least four characters.';
        _searchResults = const [];
      });
      return;
    }
    _reverseDebounce?.cancel();
    _requestGeneration++;
    _service.cancelPending();
    final generation = _requestGeneration;
    setState(() {
      _searching = true;
      _loadingAddress = false;
      _searchResults = const [];
      _error = null;
    });
    try {
      final results = await _service.search(query);
      if (!mounted || generation != _requestGeneration || results == null) {
        return;
      }
      setState(() {
        _searching = false;
        _searchResults = results;
        if (results.isEmpty) {
          _error = _isAr
              ? 'لم يتم العثور على عنوان مطابق.'
              : 'No matching address was found.';
        }
      });
    } on NationalAddressServiceException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _searching = false;
        _error = error.localized(_isAr);
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _searching = false;
        _error = _isAr
            ? 'تعذر البحث عن العنوان. تحقق من الاتصال وحاول مجددًا.'
            : 'Could not search addresses. Check your connection and retry.';
      });
    }
  }

  void _submitSearch() {
    FocusScope.of(context).unfocus();
    unawaited(_search());
  }

  void _selectAddress(NationalAddressModel address) {
    final latitude = address.latitude;
    final longitude = address.longitude;
    if (latitude == null || longitude == null) {
      setState(() {
        _selected = address;
        _searchResults = const [];
        _error = _isAr
            ? 'العنوان لا يحتوي على إحداثيات يمكن عرضها على الخريطة.'
            : 'This address has no coordinates to display on the map.';
      });
      return;
    }
    FocusScope.of(context).unfocus();
    final point = LatLng(latitude, longitude);
    _requestGeneration++;
    _service.cancelPending();
    _mapController.move(point, 17);
    setState(() {
      _center = point;
      _selected = address;
      _searchResults = const [];
      _searchController.text = address.shortAddress ?? '';
      _searching = false;
      _loadingAddress = false;
      _error = null;
    });
  }

  Future<void> _locateCurrentPosition() async {
    _reverseDebounce?.cancel();
    _requestGeneration++;
    _service.cancelPending();
    setState(() {
      _locating = true;
      _searching = false;
      _loadingAddress = false;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _locating = false);
        await _showSettingsPrompt(locationService: true);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locating = false);
        await _showSettingsPrompt(locationService: false);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      final point = LatLng(position.latitude, position.longitude);
      _requestGeneration++;
      _service.cancelPending();
      _mapController.move(point, 17);
      setState(() {
        _center = point;
        _selected = NationalAddressModel(
          latitude: point.latitude,
          longitude: point.longitude,
        );
        _searchResults = const [];
        _locating = false;
        _error = null;
      });
      _scheduleReverseGeocode(point);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _error = error is StateError
            ? error.message
            : (_isAr
                ? 'تعذر تحديد موقعك الحالي. تحقق من إعدادات الموقع.'
                : 'Could not get your location. Check location settings.');
      });
    }
  }

  void _scheduleReverseGeocode(LatLng point) {
    _reverseDebounce?.cancel();
    _requestGeneration++;
    _service.cancelPending();
    final generation = _requestGeneration;
    _reverseDebounce = Timer(const Duration(milliseconds: 800), () {
      unawaited(_reverseGeocode(point, generation));
    });
  }

  Future<void> _showSettingsPrompt({required bool locationService}) async {
    if (!mounted) return;
    final openSettings = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          locationService
              ? (_isAr ? 'خدمة الموقع مغلقة' : 'Location is turned off')
              : (_isAr
                  ? 'صلاحية الموقع مطلوبة'
                  : 'Location permission required'),
        ),
        content: Text(
          locationService
              ? (_isAr
                  ? 'فعّل خدمة الموقع في الجهاز لتحديد موقعك الحالي.'
                  : 'Enable location services to find your current position.')
              : (_isAr
                  ? 'افتح إعدادات التطبيق واسمح بالوصول إلى الموقع أثناء الاستخدام.'
                  : 'Open app settings and allow location access while using the app.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_isAr ? 'ليس الآن' : 'Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_isAr ? 'فتح الإعدادات' : 'Open settings'),
          ),
        ],
      ),
    );
    if (openSettings != true) return;
    if (locationService) {
      await Geolocator.openLocationSettings();
    } else {
      await openAppSettings();
    }
  }

  Future<void> _openDetailedAddressSearch() async {
    _reverseDebounce?.cancel();
    _requestGeneration++;
    _service.cancelPending();
    setState(() {
      _searching = false;
      _loadingAddress = false;
    });
    final address = await showAppDialog<NationalAddressModel>(
      context: context,
      builder: (context) => _DetailedAddressDialog(
        isAr: _isAr,
        service: _service,
      ),
    );
    if (!mounted || address == null) return;
    _selectAddress(address);
  }

  void _confirmSelection() {
    final address = _selected ?? const NationalAddressModel();
    WebInAppNav.runProgrammaticPop(
      () => Navigator.of(context).pop(
        address.copyWith(
          latitude: _center.latitude,
          longitude: _center.longitude,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final address = _selected ?? const NationalAddressModel();
    final keyboardOpen = AppKeyboardInset.isOpen(context) ||
        AppKeyboardInset.rawInsetOf(context) > 48;
    final details = <String>[
      if ((address.shortAddress ?? '').trim().isNotEmpty)
        '${_isAr ? 'العنوان المختصر' : 'Short address'}: ${address.shortAddress}',
      if ((address.buildingNumber ?? '').trim().isNotEmpty)
        '${_isAr ? 'رقم المبنى' : 'Building'}: ${address.buildingNumber}',
      if ((address.street ?? '').trim().isNotEmpty) address.street!,
      if ((address.district ?? '').trim().isNotEmpty) address.district!,
      if ((address.city ?? '').trim().isNotEmpty) address.city!,
      if ((address.postalCode ?? '').trim().isNotEmpty)
        '${_isAr ? 'الرمز البريدي' : 'Postal code'}: ${address.postalCode}',
      if ((address.additionalNumber ?? '').trim().isNotEmpty)
        '${_isAr ? 'الرقم الإضافي' : 'Additional number'}: ${address.additionalNumber}',
    ];

    return Scaffold(
      appBar: AppBar(
        leading: const AppPageCloseButton(),
        title: Text(_isAr ? 'العنوان الوطني' : 'National address'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: widget.initialLatitude != null
                  ? 16
                  : (widget.kingdomOverview ? 5.2 : 12),
              onMapReady: () {
                if (mounted) setState(() => _mapReady = true);
                if (widget.initialLatitude != null) {
                  _scheduleReverseGeocode(_center);
                }
              },
              onPositionChanged: _onPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.aqar_user',
                maxNativeZoom: 19,
              ),
            ],
          ),
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Icon(
                  Icons.location_pin,
                  size: 48,
                  color: cs.error,
                  shadows: const [
                    Shadow(color: Colors.white, blurRadius: 6),
                  ],
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 12,
            start: 12,
            end: 12,
            child: Column(
              children: [
                Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: AqarTextField(
                          controller: _searchController,
                          enabled: !_searching,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _submitSearch(),
                          decoration: InputDecoration(
                            hintText: _isAr
                                ? 'ابحث بالعنوان المختصر أو اسم الموقع'
                                : 'Search by short address or place',
                            prefixIcon: const Icon(Icons.search),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _isAr
                            ? 'تحقق من عنوان تفصيلي'
                            : 'Verify detailed address',
                        onPressed:
                            _searching ? null : _openDetailedAddressSearch,
                        icon: const Icon(Icons.fact_check_outlined),
                      ),
                      IconButton(
                        tooltip: _isAr ? 'بحث' : 'Search',
                        onPressed: _searching ? null : _submitSearch,
                        icon: _searching
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.arrow_forward),
                      ),
                    ],
                  ),
                ),
                if (_searchResults.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final result = _searchResults[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined),
                            title: Text(
                              result.shortAddress ?? result.displayAddress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              result.displayAddress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectAddress(result),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!keyboardOpen)
            PositionedDirectional(
              end: 14,
              bottom: 220,
              child: FloatingActionButton.small(
                heroTag: 'national_address_current_location',
                onPressed: _locating ? null : _locateCurrentPosition,
                tooltip: _isAr ? 'موقعي الحالي' : 'My current location',
                child: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
              ),
            ),
          if (!keyboardOpen)
            PositionedDirectional(
              start: 10,
              bottom: 194,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(
                        alpha: 0.9,
                      ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              ),
            ),
          if (!keyboardOpen)
            Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                color: cs.surface,
                elevation: 8,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, color: cs.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _isAr
                                    ? 'حرّك الخريطة لتحديد الموقع'
                                    : 'Move the map to select a location',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (_loadingAddress)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (details.isNotEmpty)
                          Text(
                            details.join(' • '),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          )
                        else
                          Text(
                            _isAr
                                ? 'يمكن اعتماد النقطة يدويًا أو البحث عن عنوان عند تهيئة خدمة سُبل.'
                                : 'You can confirm the pin manually or search after configuring SPL.',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: cs.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _mapReady ? _confirmSelection : null,
                          icon: const Icon(Icons.check),
                          label: Text(
                              _isAr ? 'اعتماد العنوان' : 'Use this address'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailedAddressDialog extends StatefulWidget {
  const _DetailedAddressDialog({
    required this.isAr,
    required this.service,
  });

  final bool isAr;
  final NationalAddressService service;

  @override
  State<_DetailedAddressDialog> createState() => _DetailedAddressDialogState();
}

class _DetailedAddressDialogState extends State<_DetailedAddressDialog> {
  final _building = TextEditingController();
  final _street = TextEditingController();
  final _district = TextEditingController();
  final _city = TextEditingController();
  final _postalCode = TextEditingController();
  final _additionalNumber = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _building.dispose();
    _street.dispose();
    _district.dispose();
    _city.dispose();
    _postalCode.dispose();
    _additionalNumber.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await widget.service.verifyAddress(
        buildingNumber: _building.text,
        streetName: _street.text,
        district: _district.text,
        city: _city.text,
        postalCode: _postalCode.text,
        additionalNumber: _additionalNumber.text,
      );
      if (!mounted) return;
      if (results == null || results.isEmpty) {
        setState(() {
          _busy = false;
          _error = widget.isAr
              ? 'لم يتم العثور على عنوان مطابق.'
              : 'No matching address was found.';
        });
        return;
      }
      Navigator.of(context).pop(results.first);
    } on NationalAddressServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.localized(widget.isAr);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = widget.isAr
            ? 'تعذر التحقق من العنوان. تحقق من الاتصال وحاول مجددًا.'
            : 'Could not verify the address. Check your connection and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    return AlertDialog(
      scrollable: true,
      title: Text(isAr ? 'التحقق من عنوان تفصيلي' : 'Verify detailed address'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in <(TextEditingController, String)>[
            (_building, isAr ? 'رقم المبنى' : 'Building number'),
            (_street, isAr ? 'اسم الشارع' : 'Street name'),
            (_district, isAr ? 'الحي' : 'District'),
            (_city, isAr ? 'المدينة' : 'City'),
            (_postalCode, isAr ? 'الرمز البريدي' : 'Postal code'),
            (_additionalNumber, isAr ? 'الرقم الإضافي' : 'Additional number'),
          ]) ...[
            AqarTextField(
              controller: entry.$1,
              enabled: !_busy,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: entry.$2),
            ),
            const SizedBox(height: 8),
          ],
          if (_error != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(isAr ? 'إلغاء' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isAr ? 'تحقق' : 'Verify'),
        ),
      ],
    );
  }
}
