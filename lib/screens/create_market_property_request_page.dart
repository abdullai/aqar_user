import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/haptics/app_haptics.dart';
import '../core/input/input_normalizers.dart' as input_norm;
import '../core/permissions/runtime_permission_helper.dart';
import '../core/input/saudi_input_formatters.dart';
import '../core/listing/property_type_catalog.dart';
import '../core/utils/app_money.dart';
import '../core/utils/profile_greeting_from_row.dart';
import '../l10n/app_localizations.dart';
import '../models/market_property_request_row.dart';
import '../models/market_property_request_priority.dart';
import '../models/saudi_location.dart';
import '../services/saudi_location_hierarchy.dart';
import '../services/saudi_locations_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/budget_text_field.dart';
import '../widgets/searchable_select_field.dart';
import '../main.dart' show suspendAutoLock;
import 'map_picker_page.dart';

enum _CoverPickSource { gallery, camera, files }

/// نموذج خفيف لنشر «طلب عقاري» (منفصل عن شاشة إضافة الإعلان).
class CreateMarketPropertyRequestPage extends StatefulWidget {
  final String userId;
  final String lang;
  final MarketPropertyRequestRow? initialRequest;

  const CreateMarketPropertyRequestPage({
    super.key,
    required this.userId,
    required this.lang,
    this.initialRequest,
  });

  bool get isAr => lang == 'ar';

  @override
  State<CreateMarketPropertyRequestPage> createState() =>
      _CreateMarketPropertyRequestPageState();
}

class _CreateMarketPropertyRequestPageState
    extends State<CreateMarketPropertyRequestPage> {
  final _sb = Supabase.instance.client;
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetMinCtrl = TextEditingController();
  final _budgetMaxCtrl = TextEditingController();
  final _areaMinCtrl = TextEditingController();
  final _publicNameCtrl = TextEditingController();
  final _districtsCtrl = TextEditingController();

  bool _purchase = true;
  MarketPropertyRequestPriority _requestPriority =
      MarketPropertyRequestPriority.standard;
  String _typeKey = 'villa';
  late String _typeGroupId = PropertyTypeCatalog.groupIdForCode(_typeKey);

  /// مفتاح ثابت يطابق فلتر الرئيسية: `city_en`.
  String _cityKey = '';
  String? _selectedRegion;
  String? _selectedGovernorate;
  double? _selectedLat;
  double? _selectedLng;

  /// مدة الإيجار عند اختيار «إيجار».
  String _rentTerm = 'monthly';
  int? _bedrooms;
  int? _bathrooms;
  final Map<String, bool> _requestAmenityToggles = {
    'pool': false,
    'gym': false,
    'elevator': false,
    'security': false,
    'garden': false,
    'balcony': false,
    'ac': false,
    'parking': false,
    'maid_room': false,
    'driver_room': false,
  };
  bool _preferNew = false;
  bool _saving = false;
  bool _locationsLoading = true;
  Uint8List? _coverBytes;
  String? _coverFileName;

  int _step = 0;
  static const int _stepCount = 5;
  bool _pickingCover = false;

  List<SaudiLocation> _locations = [];
  SaudiLocationHierarchy? _hierarchy;
  Map<String, dynamic>? _profileRow;
  String _profileAvatarUrl = '';

  static final _moneyInputFormatters = <TextInputFormatter>[
    LatinDecimalNumberFormatter(),
  ];

  bool get _isAr => widget.isAr;
  bool get _isEditing => widget.initialRequest != null;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _budgetMinCtrl.dispose();
    _budgetMaxCtrl.dispose();
    _areaMinCtrl.dispose();
    _publicNameCtrl.dispose();
    _districtsCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _hydrateFromInitialRequest();
    _typeGroupId = PropertyTypeCatalog.groupIdForCode(_typeKey);
    final codes = PropertyTypeCatalog.entriesForGroupMerged(_typeGroupId)
        .map((e) => (e['code'] ?? '').trim())
        .where((c) => c.isNotEmpty)
        .toList();
    if (codes.isNotEmpty && !codes.contains(_typeKey)) {
      _typeKey = codes.first;
    }
    unawaited(_loadLocations());
    unawaited(_loadProfileRow());
    if (_requestPriority == MarketPropertyRequestPriority.flexible) {
      _requestPriority = MarketPropertyRequestPriority.standard;
    }
  }

  void _hydrateFromInitialRequest() {
    final r = widget.initialRequest;
    if (r == null) return;
    _titleCtrl.text = r.title;
    _descCtrl.text = (r.description ?? '').trim();
    _budgetMinCtrl.text = _numberForField(r.budgetMin);
    _budgetMaxCtrl.text = _numberForField(r.budgetMax);
    _areaMinCtrl.text = _numberForField(r.areaMinM2);
    _publicNameCtrl.text = (r.requesterPublicName ?? '').trim();
    _districtsCtrl.text = r.districts.join(_isAr ? '، ' : ', ');
    _purchase = r.purpose != 'rent';
    _requestPriority =
        r.requestPriority == MarketPropertyRequestPriority.flexible
            ? MarketPropertyRequestPriority.standard
            : r.requestPriority;
    _typeKey = r.propertyType.trim().isEmpty ? 'villa' : r.propertyType.trim();
    _typeGroupId = PropertyTypeCatalog.groupIdForCode(_typeKey);
    _cityKey = r.city.trim();

    final details = r.details;
    final rent = (details['rent_term'] ?? '').toString().trim();
    if (rent.isNotEmpty) _rentTerm = rent;
    final nestedLocation = details['location'];
    _selectedLat = _numFromAny(details['lat']) ??
        (nestedLocation is Map ? _numFromAny(nestedLocation['lat']) : null);
    _selectedLng = _numFromAny(details['lng']) ??
        (nestedLocation is Map ? _numFromAny(nestedLocation['lng']) : null);
    _bedrooms = _intFromAny(details['bedrooms']);
    _bathrooms = _intFromAny(details['bathrooms']);
    final amenities = details['amenities'];
    if (amenities is Map) {
      for (final key in _requestAmenityToggles.keys) {
        _requestAmenityToggles[key] = amenities[key] == true;
      }
    }
  }

  static String _numberForField(num? value) {
    if (value == null) return '';
    final d = value.toDouble();
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toString();
  }

  static double? _numFromAny(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  static int? _intFromAny(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  Future<void> _loadLocations() async {
    setState(() => _locationsLoading = true);
    try {
      final all = await SaudiLocationsService.instance.loadAll();
      if (!mounted) return;
      final h = SaudiLocationHierarchy.build(all, isAr: _isAr);
      String? selReg;
      String? selGov;
      final hit = _locationForCityKey(_cityKey);
      if (hit != null) {
        selReg = _isAr ? hit.regionAr.trim() : hit.regionEn.trim();
        final rawG =
            _isAr ? hit.governorateAr?.trim() : hit.governorateEn?.trim();
        final g = (rawG != null && rawG.isNotEmpty) ? rawG : selReg;
        selGov = g;
      }
      setState(() {
        _locations = all;
        _hierarchy = h;
        _locationsLoading = false;
        _selectedRegion = selReg;
        _selectedGovernorate = selGov;
      });
      _syncInitialCityAfterLocations();
    } catch (_) {
      if (mounted) {
        setState(() {
          _locations = [];
          _hierarchy = null;
          _locationsLoading = false;
        });
      }
    }
  }

  void _syncInitialCityAfterLocations() {
    final r = widget.initialRequest;
    if (r == null || _locations.isEmpty) return;
    final rawCity = r.city.trim();
    if (rawCity.isEmpty) return;
    SaudiLocation? hit;
    for (final loc in _locations) {
      if (loc.cityEn.trim().toLowerCase() == rawCity.toLowerCase() ||
          loc.cityAr.trim() == rawCity) {
        hit = loc;
        break;
      }
    }
    if (hit == null || !mounted) return;
    final reg = _isAr ? hit.regionAr.trim() : hit.regionEn.trim();
    final rawG = _isAr ? hit.governorateAr?.trim() : hit.governorateEn?.trim();
    final gov = (rawG != null && rawG.isNotEmpty) ? rawG : reg;
    setState(() {
      _cityKey = hit!.cityEn;
      _selectedRegion = reg.isEmpty ? null : reg;
      _selectedGovernorate = gov.isEmpty ? null : gov;
    });
  }

  List<String> _districtsForSubmit() {
    return _districtsCtrl.text
        .replaceAll('،', ',')
        .split(RegExp(r'[,;\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static const Set<String> _kResidentialDetailTypes = {
    'villa',
    'apartment',
    'floor',
    'traditional_house',
    'chalet',
    'rest_house',
    'palace',
    'suite',
    'room',
    'apartment_building',
    'residential_tower',
  };

  bool _wantsResidentialDetailFields() =>
      _kResidentialDetailTypes.contains(_typeKey);

  String _amenityLabel(String key) {
    switch (key) {
      case 'pool':
        return _isAr ? 'مسبح' : 'Pool';
      case 'gym':
        return _isAr ? 'صالة رياضية' : 'Gym';
      case 'elevator':
        return _isAr ? 'مصعد' : 'Elevator';
      case 'security':
        return _isAr ? 'أمن' : 'Security';
      case 'garden':
        return _isAr ? 'حديقة' : 'Garden';
      case 'balcony':
        return _isAr ? 'شرفة' : 'Balcony';
      case 'ac':
        return _isAr ? 'تكييف' : 'A/C';
      case 'parking':
        return _isAr ? 'موقف' : 'Parking';
      case 'maid_room':
        return _isAr ? 'غرفة خادمة' : 'Maid room';
      case 'driver_room':
        return _isAr ? 'غرفة سائق' : 'Driver room';
      default:
        return key;
    }
  }

  Map<String, dynamic> _detailsPayloadForInsert() {
    final out = <String, dynamic>{};
    if (!_purchase) {
      out['rent_term'] = _rentTerm;
    }
    if (_selectedLat != null && _selectedLng != null) {
      out['lat'] = _selectedLat;
      out['lng'] = _selectedLng;
      out['location'] = {
        'lat': _selectedLat,
        'lng': _selectedLng,
        'source': 'map_picker',
      };
    }
    if (_wantsResidentialDetailFields()) {
      if (_bedrooms != null) out['bedrooms'] = _bedrooms;
      if (_bathrooms != null) out['bathrooms'] = _bathrooms;
      final am = <String, bool>{};
      _requestAmenityToggles.forEach((k, v) {
        if (v) am[k] = true;
      });
      if (am.isNotEmpty) out['amenities'] = am;
    }
    return out;
  }

  List<String> get _governorateOptions {
    final r = _selectedRegion;
    if (r == null || r.isEmpty || _hierarchy == null) return const [];
    return _hierarchy!.governoratesByRegion[r] ?? const [];
  }

  List<String> get _cityOptions {
    final g = _selectedGovernorate;
    if (g == null || g.isEmpty || _hierarchy == null) return const [];
    return _hierarchy!.citiesByGovernorate[g] ?? const [];
  }

  /// تسمية المدينة الحالية إن وُجدت ضمن قائمة المدن للمحافظة المختارة.
  String? get _selectedCityLabelInList {
    if (_cityKey.isEmpty) return null;
    final labels = _cityOptions;
    if (labels.isEmpty) return null;
    final L = _locationForCityKey(_cityKey);
    if (L == null) return null;
    final lab = _isAr ? L.cityAr.trim() : L.cityEn.trim();
    return labels.contains(lab) ? lab : null;
  }

  String? get _effectiveTypeKeyForDropdown {
    final codes = PropertyTypeCatalog.entriesForGroupMerged(_typeGroupId)
        .map((e) => (e['code'] ?? '').trim())
        .where((c) => c.isNotEmpty)
        .toList();
    if (codes.isEmpty) return null;
    return codes.contains(_typeKey) ? _typeKey : codes.first;
  }

  Future<void> _onRegionSelected(String? value) async {
    if (value == null) return;
    setState(() {
      _selectedRegion = value;
      _selectedGovernorate = null;
      _cityKey = '';
    });
    final govList = _hierarchy?.governoratesByRegion[value] ?? const [];
    if (govList.length == 1) {
      await _onGovernorateSelected(govList.first);
    }
  }

  Future<void> _onGovernorateSelected(String? value) async {
    if (value == null) return;
    setState(() {
      _selectedGovernorate = value;
      _cityKey = '';
    });
    final cities = _hierarchy?.citiesByGovernorate[value] ?? const [];
    if (cities.length == 1) {
      _onCitySelected(cities.first);
    }
  }

  void _onCitySelected(String? cityLabel) {
    if (cityLabel == null || _selectedRegion == null) return;
    final reg = _selectedRegion!;
    final govKey = _selectedGovernorate ?? reg;
    SaudiLocation? found;
    for (final L in _locations) {
      final r = _isAr ? L.regionAr.trim() : L.regionEn.trim();
      final rawG = _isAr ? L.governorateAr?.trim() : L.governorateEn?.trim();
      final g = (rawG != null && rawG.isNotEmpty) ? rawG : r;
      final c = _isAr ? L.cityAr.trim() : L.cityEn.trim();
      if (r == reg && g == govKey && c == cityLabel) {
        found = L;
        break;
      }
    }
    if (found != null) {
      setState(() => _cityKey = found!.cityEn);
    }
  }

  void _setTypeGroup(String groupId) {
    final entries = PropertyTypeCatalog.entriesForGroupMerged(groupId);
    final codes = entries
        .map((e) => (e['code'] ?? '').trim())
        .where((c) => c.isNotEmpty)
        .toList();
    setState(() {
      _typeGroupId = groupId;
      if (!codes.contains(_typeKey)) {
        _typeKey = codes.isNotEmpty ? codes.first : 'villa';
      }
    });
  }

  Future<void> _loadProfileRow() async {
    try {
      final row = await _sb
          .from('users_profiles')
          .select(
            'first_name_ar,second_name_ar,third_name_ar,fourth_name_ar,'
            'first_name_en,second_name_en,third_name_en,fourth_name_en,'
            'full_name_ar,full_name_en,full_name,username,avatar_url',
          )
          .eq('user_id', widget.userId)
          .maybeSingle();
      if (!mounted || row == null) return;
      _profileRow = Map<String, dynamic>.from(row);
      final av = (_profileRow!['avatar_url'] ?? '').toString().trim();
      final d = ProfileGreetingFromRow.displayName(_profileRow!, isAr: _isAr);
      if (d != null && d.isNotEmpty) {
        setState(() {
          _profileAvatarUrl = av;
          if (!_isEditing || _publicNameCtrl.text.trim().isEmpty) {
            _publicNameCtrl.text = d;
          }
        });
      } else if (av.isNotEmpty) {
        setState(() => _profileAvatarUrl = av);
      }
    } catch (_) {}
  }

  SaudiLocation? _locationForCityKey(String key) {
    for (final L in _locations) {
      if (L.cityEn == key) return L;
    }
    return null;
  }

  String _cityForSubmit() {
    final L = _locationForCityKey(_cityKey);
    if (L == null) return _cityKey;
    return _isAr ? L.cityAr : L.cityEn;
  }

  Future<void> _openMapForCity() async {
    LatLng? initial;
    final cur = _locationForCityKey(_cityKey);
    if (cur != null && cur.lat != 0 && cur.lng != 0) {
      initial = LatLng(cur.lat, cur.lng);
    }
    final res = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => MapPickerPage(
          initial: initial,
          isAr: _isAr,
          kingdomOverview: initial == null,
          pinTitle: _titleCtrl.text.trim().isEmpty
              ? (_isAr ? 'طلب عقاري جديد' : 'New property request')
              : _titleCtrl.text.trim(),
          pinSubtitle: _cityForSubmit(),
          pinKindLabel: _purchase
              ? (_isAr ? 'طلب شراء' : 'Purchase request')
              : (_isAr ? 'طلب إيجار' : 'Rent request'),
          pinAmountLabel: _requestBudgetLabel(),
        ),
      ),
    );
    if (!mounted || res == null) return;
    final lat = (res['lat'] as num?)?.toDouble();
    final lng = (res['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final hit = await SaudiLocationsService.instance.findNearest(lat, lng);
    if (!mounted || hit == null) return;
    final reg = _isAr ? hit.regionAr.trim() : hit.regionEn.trim();
    final rawG = _isAr ? hit.governorateAr?.trim() : hit.governorateEn?.trim();
    final gov = (rawG != null && rawG.isNotEmpty) ? rawG : reg;
    setState(() {
      _cityKey = hit.cityEn;
      _selectedRegion = reg.isEmpty ? null : reg;
      _selectedGovernorate = gov.isEmpty ? null : gov;
      _selectedLat = lat;
      _selectedLng = lng;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          _isAr ? 'تم اختيار: ${hit.cityAr}' : 'Selected: ${hit.cityEn}',
        ),
      ),
    );
  }

  double? _parseMoney(String s) {
    final t = input_norm
        .normalizeAsciiDigits(s.trim())
        .replaceAll(',', '')
        .replaceAll('٬', '')
        .replaceAll('٫', '.')
        .replaceAll(AppMoney.saudiRiyalSignUnicode, '')
        .replaceAll(RegExp(r'[^0-9.]'), '');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  String? _requestBudgetLabel() {
    final min = _parseMoney(_budgetMinCtrl.text);
    final max = _parseMoney(_budgetMaxCtrl.text);
    if (min == null && max == null) return null;
    const cur = AppMoney.saudiRiyalSignUnicode;
    if (min != null && max != null) {
      return '${min.toStringAsFixed(0)} - ${max.toStringAsFixed(0)} $cur';
    }
    if (max != null) return '${max.toStringAsFixed(0)} $cur';
    return '${min!.toStringAsFixed(0)}+ $cur';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  /// تحقق قبل الانتقال من خطوة [step] الحالية إلى التالية.
  bool _validateStepBeforeLeave(int step) {
    switch (step) {
      case 0:
        if (_titleCtrl.text.trim().isEmpty) {
          _showSnack(_isAr ? 'أدخل عنواناً للطلب' : 'Enter a title');
          return false;
        }
        return true;
      case 1:
        return true;
      case 2:
        if (_locations.isEmpty && !_locationsLoading) {
          _showSnack(
            _isAr
                ? 'تعذر تحميل بيانات المدن. تحقق من الاتصال وحاول مجدداً.'
                : 'Could not load city data. Check your connection and retry.',
          );
          return false;
        }
        if (_cityKey.isEmpty ||
            _selectedRegion == null ||
            _selectedRegion!.isEmpty ||
            _selectedGovernorate == null ||
            _selectedGovernorate!.isEmpty) {
          _showSnack(
            _isAr
                ? 'اختر المنطقة والمحافظة والمدينة (أو حدّد على الخريطة)'
                : 'Choose region, governorate, and city (or pick on the map)',
          );
          return false;
        }
        return true;
      case 3:
        final min = _parseMoney(_budgetMinCtrl.text);
        final max = _parseMoney(_budgetMaxCtrl.text);
        if (min != null && max != null && min > max) {
          _showSnack(
            _isAr
                ? 'ميزانية «من» يجب ألا تتجاوز «إلى»'
                : 'Budget min must not exceed max',
          );
          return false;
        }
        return true;
      case 4:
        if (_publicNameCtrl.text.trim().isEmpty) {
          _showSnack(
            _isAr
                ? 'أدخل الاسم الرباعي / المعروض للمهتمين'
                : 'Enter your display name for responders',
          );
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _goNextStep() {
    if (!_validateStepBeforeLeave(_step)) return;
    if (_step >= _stepCount - 1) return;
    setState(() => _step++);
  }

  void _goPrevStep() {
    if (_step <= 0) return;
    setState(() => _step--);
  }

  Future<void> _showCoverPickMenu() async {
    if (_saving || _pickingCover) return;
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await _pickCover(source: _CoverPickSource.files);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(_isAr ? 'الاستديو' : 'Gallery'),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_pickCover(source: _CoverPickSource.gallery));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: Text(_isAr ? 'الكاميرا' : 'Camera'),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_pickCover(source: _CoverPickSource.camera));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text(_isAr ? 'اختيار من الملفات' : 'Choose files'),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_pickCover(source: _CoverPickSource.files));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickCover({required _CoverPickSource source}) async {
    if (_saving || _pickingCover) return;

    final nativeMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final t = AppLocalizations.of(context);
    if (nativeMobile && t != null) {
      if (source == _CoverPickSource.gallery) {
        final ok = await RuntimePermissionHelper.ensurePhotos(context, t: t);
        if (!ok || !mounted) return;
      } else if (source == _CoverPickSource.camera) {
        final ok = await RuntimePermissionHelper.ensureCamera(context, t: t);
        if (!ok || !mounted) return;
      }
    }

    setState(() => _pickingCover = true);
    suspendAutoLock.value = true;
    try {
      Uint8List? bytes;
      String? name;
      if (source == _CoverPickSource.files || kIsWeb || !nativeMobile) {
        final res = await FilePicker.platform.pickFiles(
          allowMultiple: false,
          type: FileType.image,
          withData: true,
        );
        if (!mounted) return;
        if (res != null && res.files.isNotEmpty) {
          final f = res.files.first;
          bytes = f.bytes;
          name = f.name;
        }
      } else {
        final picker = ImagePicker();
        if (source == _CoverPickSource.gallery) {
          final x = await picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 1600,
            maxHeight: 1600,
            imageQuality: 85,
          );
          if (!mounted || x == null) return;
          bytes = await x.readAsBytes();
          name = x.name.isNotEmpty
              ? x.name
              : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        } else if (source == _CoverPickSource.camera) {
          final x = await picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 90,
          );
          if (!mounted || x == null) return;
          bytes = await x.readAsBytes();
          name = x.name.isNotEmpty
              ? x.name
              : 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg';
        }
      }
      if (!mounted) return;
      if (bytes != null && bytes.isNotEmpty) {
        setState(() {
          _coverBytes = bytes;
          _coverFileName = name;
        });
      }
    } finally {
      suspendAutoLock.value = false;
      if (mounted) setState(() => _pickingCover = false);
    }
  }

  Future<void> _submit() async {
    for (var s = 0; s < _stepCount; s++) {
      if (!_validateStepBeforeLeave(s)) {
        setState(() => _step = s);
        return;
      }
    }
    final title = _titleCtrl.text.trim();
    final pub = _publicNameCtrl.text.trim();

    setState(() => _saving = true);
    try {
      String? coverPath;
      final bytes = _coverBytes;
      if (bytes != null && bytes.isNotEmpty) {
        final name = (_coverFileName ?? 'cover.jpg').toLowerCase();
        final ext = name.endsWith('.png')
            ? 'png'
            : name.endsWith('.webp')
                ? 'webp'
                : 'jpg';
        final mime = ext == 'png'
            ? 'image/png'
            : ext == 'webp'
                ? 'image/webp'
                : 'image/jpeg';
        coverPath =
            'market-requests/${widget.userId}/${const Uuid().v4()}.$ext';
        await _sb.storage.from('property-images').uploadBinary(
              coverPath,
              bytes,
              fileOptions: FileOptions(
                upsert: false,
                contentType: mime,
              ),
            );
      }

      Future<void> doInsert(Map<String, dynamic> payload) async {
        try {
          await _sb.from('market_property_requests').insert(payload);
        } on PostgrestException catch (e) {
          final detail = '${e.message} ${e.details ?? ''}'.toLowerCase();
          if (detail.contains('request_priority')) {
            payload.remove('request_priority');
            await _sb.from('market_property_requests').insert(payload);
          } else {
            rethrow;
          }
        }
      }

      var row = <String, dynamic>{
        'requester_id': widget.userId,
        if (!_isEditing) 'status': 'published',
        'request_priority': _requestPriority.wireValue,
        'title': title,
        'description':
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'purpose': _purchase ? 'purchase' : 'rent',
        'property_type': _typeKey,
        'city': _cityForSubmit(),
        'districts': _districtsForSubmit(),
        'budget_min': _parseMoney(_budgetMinCtrl.text),
        'budget_max': _parseMoney(_budgetMaxCtrl.text),
        'area_min_m2': _parseMoney(_areaMinCtrl.text),
        'prefer_new': _preferNew,
        'show_requester_name': true,
        'requester_public_name': pub,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (coverPath != null) {
        row['cover_image_storage_path'] = coverPath;
      }
      final details = _detailsPayloadForInsert();
      if (details.isNotEmpty) {
        row['details_json'] = details;
      } else if (_isEditing) {
        row['details_json'] = <String, dynamic>{};
      }
      try {
        if (_isEditing) {
          await _updateExistingRequest(Map<String, dynamic>.from(row));
        } else {
          await doInsert(Map<String, dynamic>.from(row));
        }
      } on PostgrestException catch (e) {
        final detail = '${e.message} ${e.details ?? ''}'.toLowerCase();
        if (detail.contains('details_json')) {
          row.remove('details_json');
          if (_isEditing) {
            await _updateExistingRequest(Map<String, dynamic>.from(row));
          } else {
            await doInsert(Map<String, dynamic>.from(row));
          }
        } else {
          rethrow;
        }
      }
      if (!mounted) return;
      AppHaptics.medium();
      if (_isEditing) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isAr ? 'تم تحديث الطلب.' : 'Request updated.'),
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }
      final t = AppLocalizations.of(context);
      final next = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(
            t?.marketPropertySubmitSuccessTitle ??
                (_isAr ? 'تم بنجاح' : 'Success'),
          ),
          content: Text(
            t?.marketPropertySubmitSuccessBody ??
                (_isAr
                    ? 'تم تقديم طلبك العقاري بنجاح.'
                    : 'Your property request was submitted.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'another'),
              child: Text(
                t?.marketPropertySubmitAnother ??
                    (_isAr ? 'طلب عقاري آخر' : 'Another request'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'home'),
              child: Text(
                t?.marketPropertySubmitGoHome ??
                    (_isAr ? 'العودة للرئيسية' : 'Back to Home'),
              ),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(next ?? 'home');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _updateExistingRequest(Map<String, dynamic> payload) async {
    final rid = widget.initialRequest?.id.trim() ?? '';
    if (rid.isEmpty) return;
    payload.remove('requester_id');
    payload.remove('status');
    try {
      await _sb
          .from('market_property_requests')
          .update(payload)
          .eq('id', rid)
          .eq('requester_id', widget.userId);
    } on PostgrestException catch (e) {
      final detail = '${e.message} ${e.details ?? ''}'.toLowerCase();
      if (detail.contains('request_priority')) {
        payload.remove('request_priority');
        await _updateExistingRequest(payload);
        return;
      }
      if (detail.contains('updated_at')) {
        payload.remove('updated_at');
        await _updateExistingRequest(payload);
        return;
      }
      rethrow;
    }
  }

  String _priorityMenuLabel(
      AppLocalizations? t, MarketPropertyRequestPriority p) {
    if (t == null) {
      return p.wireValue;
    }
    switch (p) {
      case MarketPropertyRequestPriority.flexible:
        return t.marketRequestPriorityFlexible;
      case MarketPropertyRequestPriority.standard:
        return t.marketRequestPriorityStandard;
      case MarketPropertyRequestPriority.priority:
        return t.marketRequestPriorityPriority;
      case MarketPropertyRequestPriority.urgent:
        return t.marketRequestPriorityUrgent;
      case MarketPropertyRequestPriority.immediate:
        return t.marketRequestPriorityImmediate;
    }
  }

  String _wizardStepHeading(int step) {
    switch (step) {
      case 0:
        return _isAr ? 'المعلومات الأساسية' : 'Basics';
      case 1:
        return _isAr ? 'نوع العقار' : 'Property type';
      case 2:
        return _isAr ? 'الموقع' : 'Location';
      case 3:
        return _isAr ? 'الميزانية والمواصفات' : 'Budget & details';
      case 4:
        return _isAr ? 'صورة وخصوصية' : 'Image & privacy';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    final h = _hierarchy;
    final regions = h?.regionOptions ?? const <String>[];
    final govList = _governorateOptions;
    final cityList = _cityOptions;
    const kTh = SaudiLocationHierarchy.kLocSearchThreshold;
    final busy = _saving || _pickingCover;

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        );

    final stepBody = <Widget>[
      if (_step == 0) ...[
        Text(
          _isAr
              ? 'يظهر طلبك في الرئيسية للمهتمين. أكمل الخطوات بالترتيب.'
              : 'Your request appears on the home feed. Complete the steps in order.',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<MarketPropertyRequestPriority>(
          value: _requestPriority,
          decoration: InputDecoration(
            labelText: t?.marketRequestUrgencyTitle ??
                (_isAr ? 'درجة الإلحاح' : 'Request urgency'),
            helperText: t?.marketRequestUrgencyHint ??
                (_isAr
                    ? 'تؤثر على ترتيب ظهور الطلب في الرئيسية.'
                    : 'Affects how prominently the request appears on home.'),
            border: const OutlineInputBorder(),
          ),
          items: MarketPropertyRequestPriority.values
              .where((p) => p != MarketPropertyRequestPriority.flexible)
              .map(
                (p) => DropdownMenuItem(
                  value: p,
                  child: Text(_priorityMenuLabel(t, p)),
                ),
              )
              .toList(),
          onChanged: busy
              ? null
              : (v) {
                  if (v == null) return;
                  setState(() => _requestPriority = v);
                },
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _titleCtrl,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: _isAr ? 'عنوان الطلب *' : 'Request title *',
            border: const OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descCtrl,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: _isAr ? 'تفاصيل إضافية' : 'More details',
            border: const OutlineInputBorder(),
          ),
          minLines: 2,
          maxLines: 5,
        ),
        const SizedBox(height: 14),
        Text(
          _isAr ? 'الغرض' : 'Purpose',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        AbsorbPointer(
          absorbing: busy,
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                label: Text(_isAr ? 'شراء' : 'Buy'),
              ),
              ButtonSegment(
                value: false,
                label: Text(_isAr ? 'إيجار' : 'Rent'),
              ),
            ],
            selected: {_purchase},
            onSelectionChanged: (s) {
              setState(() {
                _purchase = s.first;
                if (!_purchase && _rentTerm.isEmpty) {
                  _rentTerm = 'monthly';
                }
              });
            },
          ),
        ),
        if (!_purchase) ...[
          const SizedBox(height: 14),
          Text(
            _isAr ? 'مدة الإيجار' : 'Rent period',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          AbsorbPointer(
            absorbing: busy,
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'daily',
                  label: Text(_isAr ? 'يومي' : 'Daily'),
                ),
                ButtonSegment(
                  value: 'weekly',
                  label: Text(_isAr ? 'أسبوعي' : 'Weekly'),
                ),
                ButtonSegment(
                  value: 'monthly',
                  label: Text(_isAr ? 'شهري' : 'Monthly'),
                ),
                ButtonSegment(
                  value: 'yearly',
                  label: Text(_isAr ? 'سنوي' : 'Yearly'),
                ),
              ],
              selected: {_rentTerm},
              onSelectionChanged: (s) {
                final v = s.first;
                if (v.isNotEmpty) setState(() => _rentTerm = v);
              },
            ),
          ),
        ],
      ],
      if (_step == 1) ...[
        DropdownButtonFormField<String>(
          value: PropertyTypeCatalog.typeGroups.any((g) => g.id == _typeGroupId)
              ? _typeGroupId
              : PropertyTypeCatalog.typeGroups.first.id,
          decoration: deco(
            _isAr ? 'فئة العقار' : 'Property category',
          ),
          isExpanded: true,
          items: PropertyTypeCatalog.typeGroups
              .map(
                (g) => DropdownMenuItem(
                  value: g.id,
                  child: Text(
                    PropertyTypeCatalog.groupLabel(g.id, _isAr),
                  ),
                ),
              )
              .toList(),
          onChanged: busy
              ? null
              : (v) {
                  if (v == null) return;
                  _setTypeGroup(v);
                },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _effectiveTypeKeyForDropdown,
          decoration: deco(_isAr ? 'نوع العقار' : 'Property type'),
          isExpanded: true,
          items: PropertyTypeCatalog.entriesForGroupMerged(_typeGroupId)
              .map(
                (e) {
                  final code = (e['code'] ?? '').trim();
                  if (code.isEmpty) return null;
                  return DropdownMenuItem(
                    value: code,
                    child: Text(PropertyTypeCatalog.label(code, _isAr)),
                  );
                },
              )
              .whereType<DropdownMenuItem<String>>()
              .toList(),
          onChanged: busy
              ? null
              : (v) {
                  if (v == null) return;
                  setState(() => _typeKey = v);
                },
        ),
      ],
      if (_step == 2) ...[
        if (_locationsLoading) ...[
          const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 10),
        ],
        Text(
          _isAr
              ? 'المنطقة والمحافظة والمدينة مطلوبة. يمكنك التحديد على الخريطة.'
              : 'Region, governorate, and city are required. You can pick on the map.',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        if (!_locationsLoading && _locations.isEmpty)
          Text(
            _isAr
                ? 'تعذر تحميل المدن. تحقق من الاتصال ثم أعد فتح هذه الخطوة.'
                : 'Could not load cities. Check connection, then reopen this step.',
            style: TextStyle(color: cs.error),
          ),
        if (!_locationsLoading && _locations.isNotEmpty) ...[
          if (regions.length > kTh)
            SearchableSelectField(
              label: _isAr ? 'المنطقة *' : 'Region *',
              items: regions,
              selected: _selectedRegion,
              isAr: _isAr,
              enabled: !busy,
              allowClear: false,
              onSelected: (v) {
                unawaited(_onRegionSelected(v));
              },
            )
          else
            DropdownButtonFormField<String>(
              value:
                  _selectedRegion != null && regions.contains(_selectedRegion!)
                      ? _selectedRegion
                      : null,
              decoration: deco(_isAr ? 'المنطقة *' : 'Region *'),
              hint: Text(_isAr ? 'اختر' : 'Choose'),
              isExpanded: true,
              items: regions
                  .map(
                    (e) => DropdownMenuItem(value: e, child: Text(e)),
                  )
                  .toList(),
              onChanged: busy ? null : (v) => unawaited(_onRegionSelected(v)),
            ),
          const SizedBox(height: 10),
          if (_selectedRegion != null && govList.isNotEmpty) ...[
            if (govList.length > kTh)
              SearchableSelectField(
                label: _isAr ? 'المحافظة *' : 'Governorate *',
                items: govList,
                selected: _selectedGovernorate,
                isAr: _isAr,
                enabled: !busy,
                allowClear: false,
                onSelected: (v) {
                  unawaited(_onGovernorateSelected(v));
                },
              )
            else
              DropdownButtonFormField<String>(
                value: _selectedGovernorate != null &&
                        govList.contains(_selectedGovernorate!)
                    ? _selectedGovernorate
                    : null,
                decoration: deco(_isAr ? 'المحافظة *' : 'Governorate *'),
                hint: Text(_isAr ? 'اختر' : 'Choose'),
                isExpanded: true,
                items: govList
                    .map(
                      (e) => DropdownMenuItem(value: e, child: Text(e)),
                    )
                    .toList(),
                onChanged:
                    busy ? null : (v) => unawaited(_onGovernorateSelected(v)),
              ),
          ],
          if (_selectedGovernorate != null && cityList.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: cityList.length > kTh
                      ? SearchableSelectField(
                          label: _isAr ? 'المدينة *' : 'City *',
                          items: cityList,
                          selected: _selectedCityLabelInList,
                          isAr: _isAr,
                          enabled: !busy,
                          allowClear: false,
                          onSelected: (v) => _onCitySelected(v),
                        )
                      : DropdownButtonFormField<String>(
                          value: _selectedCityLabelInList,
                          decoration: deco(_isAr ? 'المدينة *' : 'City *'),
                          hint: Text(_isAr ? 'اختر' : 'Choose'),
                          isExpanded: true,
                          items: cityList
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(e),
                                ),
                              )
                              .toList(),
                          onChanged: busy ? null : (v) => _onCitySelected(v),
                        ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: IconButton.filledTonal(
                    tooltip: _isAr ? 'تحديد على الخريطة' : 'Pick on map',
                    onPressed: busy ? null : _openMapForCity,
                    icon: const Icon(Icons.map_outlined),
                  ),
                ),
              ],
            ),
          ],
          if (_selectedLat != null && _selectedLng != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 19,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isAr
                          ? 'تم حفظ موقع الطلب على الخريطة'
                          : 'Request map location is saved',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _districtsCtrl,
            enabled: !busy,
            decoration: InputDecoration(
              labelText: _isAr
                  ? 'أحياء مفضّلة (اختياري)'
                  : 'Preferred districts (optional)',
              hintText: _isAr
                  ? 'مثال: النرجس، الياسمين — افصل بفاصلة أو سطر'
                  : 'e.g. Al Narjis, Al Yasmin — comma or newline',
              border: const OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 3,
          ),
        ],
      ],
      if (_step == 3) ...[
        Text(
          _isAr
              ? 'الميزانية والمساحة اختيارية؛ إن أدخلت «من» و«إلى» يجب أن يكون الترتيب منطقياً.'
              : 'Budget and area are optional; if both min and max are set, min must be ≤ max.',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 520;
            final budgetRow = narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BudgetTextField(
                        controller: _budgetMinCtrl,
                        label: _isAr ? 'ميزانية من' : 'Budget min',
                        enabled: !busy,
                        inputFormatters: _moneyInputFormatters,
                      ),
                      const SizedBox(height: 10),
                      BudgetTextField(
                        controller: _budgetMaxCtrl,
                        label: _isAr ? 'ميزانية إلى' : 'Budget max',
                        enabled: !busy,
                        textInputAction: TextInputAction.next,
                        inputFormatters: _moneyInputFormatters,
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: BudgetTextField(
                          controller: _budgetMinCtrl,
                          label: _isAr ? 'ميزانية من' : 'Budget min',
                          enabled: !busy,
                          inputFormatters: _moneyInputFormatters,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: BudgetTextField(
                          controller: _budgetMaxCtrl,
                          label: _isAr ? 'ميزانية إلى' : 'Budget max',
                          enabled: !busy,
                          textInputAction: TextInputAction.next,
                          inputFormatters: _moneyInputFormatters,
                        ),
                      ),
                    ],
                  );
            return budgetRow;
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _areaMinCtrl,
          enabled: !busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _moneyInputFormatters,
          decoration: InputDecoration(
            labelText: _isAr ? 'مساحة لا تقل عن (م²)' : 'Min area (m²)',
            border: const OutlineInputBorder(),
          ),
        ),
        if (_wantsResidentialDetailFields()) ...[
          const SizedBox(height: 16),
          Text(
            _isAr ? 'تفاصيل سكنية (اختياري)' : 'Residential details (optional)',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: _bedrooms,
                  decoration: deco(_isAr ? 'غرف نوم' : 'Bedrooms'),
                  isExpanded: true,
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(_isAr ? 'غير محدد' : 'Any'),
                    ),
                    for (var n = 1; n <= 12; n++)
                      DropdownMenuItem<int?>(
                        value: n,
                        child: Text('$n'),
                      ),
                  ],
                  onChanged: busy ? null : (v) => setState(() => _bedrooms = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: _bathrooms,
                  decoration: deco(_isAr ? 'دورات مياه' : 'Bathrooms'),
                  isExpanded: true,
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(_isAr ? 'غير محدد' : 'Any'),
                    ),
                    for (var n = 1; n <= 10; n++)
                      DropdownMenuItem<int?>(
                        value: n,
                        child: Text('$n'),
                      ),
                  ],
                  onChanged:
                      busy ? null : (v) => setState(() => _bathrooms = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _isAr ? 'الخدمات المطلوبة' : 'Desired amenities',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _requestAmenityToggles.keys.map((k) {
              final on = _requestAmenityToggles[k] ?? false;
              return FilterChip(
                label: Text(_amenityLabel(k)),
                selected: on,
                onSelected: busy
                    ? null
                    : (v) => setState(() => _requestAmenityToggles[k] = v),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          value: _preferNew,
          onChanged: busy ? null : (v) => setState(() => _preferNew = v),
          title: Text(
            _isAr ? 'أفضّل عقاراً جديداً' : 'Prefer newer property',
          ),
        ),
      ],
      if (_step == 4) ...[
        Text(
          _isAr ? 'صورة للطلب (اختياري)' : 'Request image (optional)',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 72,
                height: 72,
                color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                alignment: Alignment.center,
                child: _coverBytes == null
                    ? Image.asset(
                        'assets/logo.png',
                        width: 48,
                        height: 48,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.add_photo_alternate_outlined,
                          color: cs.primary,
                        ),
                      )
                    : Image.memory(
                        _coverBytes!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : _showCoverPickMenu,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      _isAr
                          ? 'صورة (معرض / كاميرا / ملف)'
                          : 'Image (gallery / camera / file)',
                    ),
                  ),
                  if (_coverBytes != null)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                                _coverBytes = null;
                                _coverFileName = null;
                              }),
                      child: Text(
                        _isAr ? 'إزالة الصورة' : 'Remove image',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _isAr
              ? 'يُعرض اسمك للمهتمين بالطلب — إلزامي للشفافية.'
              : 'Your name is shown to responders — required for transparency.',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_profileAvatarUrl.isNotEmpty) ...[
              ClipOval(
                child: CachedNetworkImage(
                  imageUrl: _profileAvatarUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: TextField(
                controller: _publicNameCtrl,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText:
                      _isAr ? 'الاسم الرباعي / المعروض *' : 'Display name *',
                  hintText: _isAr
                      ? 'يُقترح من ملفك الشخصي ويمكن تعديله'
                      : 'Suggested from your profile; you may edit',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing
              ? (_isAr ? 'تعديل الطلب العقاري' : 'Edit property request')
              : (_isAr ? 'طلب عقاري' : 'Property request'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: (_step + 1) / _stepCount,
              ),
            ),
          ),
        ),
      ),
      body: _saving
          ? const Center(child: AppLogoLoading())
          : LayoutBuilder(
              builder: (context, constraints) {
                final padH = min(32.0, max(12.0, constraints.maxWidth * 0.04));
                final maxBody = min(constraints.maxWidth, 720.0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(padH, 12, padH, 16),
                        children: [
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: maxBody),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    '${_step + 1} / $_stepCount · ${_wizardStepHeading(_step)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: cs.primary,
                                        ),
                                  ),
                                  const SizedBox(height: 10),
                                  ...stepBody,
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_pickingCover)
                      const LinearProgressIndicator(minHeight: 2),
                    SafeArea(
                      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxBody),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (_step > 0)
                                OutlinedButton(
                                  onPressed: busy ? null : _goPrevStep,
                                  child: Text(_isAr ? 'السابق' : 'Back'),
                                ),
                              const Spacer(),
                              if (_step < _stepCount - 1)
                                FilledButton(
                                  onPressed: busy ? null : _goNextStep,
                                  child: Text(_isAr ? 'التالي' : 'Next'),
                                )
                              else
                                FilledButton(
                                  onPressed: busy ? null : _submit,
                                  child: Text(
                                    _isAr ? 'نشر الطلب' : 'Publish request',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
