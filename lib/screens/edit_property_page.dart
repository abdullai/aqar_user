// lib/screens/edit_property_page.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/permissions/runtime_permission_helper.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show suspendAutoLock;
import '../models/property.dart';
import '../shared/core/supabase_schema_selects.dart';
import '../core/input/input_normalizers.dart';
import '../core/input/saudi_input_formatters.dart';
import '../core/listing/listing_area_unit.dart';
import '../core/listing/property_type_catalog.dart';
import '../core/workflow/listing_edit_permissions.dart';
import '../core/listing/property_type_custom_registry.dart';
import '../core/utils/app_money.dart';
import '../services/watermark_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/deed_date_calendar_dialog.dart';
import '../widgets/year_built_picker_field.dart';
import '../widgets/property_type_hierarchy_picker.dart';

/// مطابقة لأسماء `saudi_locations.json` (كما في إضافة إعلان).
const List<String> _kEditQuickCityAr = ['الرياض', 'جدة', 'مكة المكرمة'];
const List<String> _kEditQuickCityEn = ['Riyadh', 'Jeddah', 'Makkah'];

class EditPropertyPage extends StatefulWidget {
  final Property property;
  final String userId;
  final String lang;

  /// وضع المسوّق: تعديل لمطابقة بيانات الهيئة بعد التصريح (قبل النشر).
  final bool marketerRegaAlignmentMode;

  const EditPropertyPage({
    super.key,
    required this.property,
    required this.userId,
    required this.lang,
    this.marketerRegaAlignmentMode = false,
  });

  @override
  State<EditPropertyPage> createState() => _EditPropertyPageState();
}

class _EditPropertyPageState extends State<EditPropertyPage> {
  final _sb = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  bool get _isAr => widget.lang.toLowerCase() != 'en';
  String get _uid => _sb.auth.currentUser?.id ?? '';
  bool get _isGuest => _uid.isEmpty;

  bool _loading = true;
  bool _saving = false;
  bool _picking = false;
  bool _uploadingVideo = false;

  String? _error;

  int _editCount = 0;
  int _maxEdits = 3;
  bool _editExhausted = false;

  late TextEditingController _title;
  late TextEditingController _desc;
  late TextEditingController _city;
  late TextEditingController _region;
  late TextEditingController _governorate;
  late TextEditingController _location;
  late TextEditingController _buildingNumber;
  late TextEditingController _addressLine;
  late TextEditingController _price;
  late TextEditingController _area;
  late TextEditingController _currentBid;
  late TextEditingController _virtualTourUrl;
  late TextEditingController _contactPhone;
  late TextEditingController _editReason;
  late TextEditingController _deedNumber;
  late TextEditingController _deedIssuer;
  final _parcelNumber = TextEditingController();
  final _boundaryNorth = TextEditingController();
  final _boundarySouth = TextEditingController();
  final _boundaryEast = TextEditingController();
  final _boundaryWest = TextEditingController();

  String _currency = 'SAR';
  ListingAreaUnit _areaUnit = ListingAreaUnit.m2;
  String _purpose = 'sale';
  DateTime? _deedDate;
  bool _negotiable = false;
  String _typeCode = 'villa';

  int? _bedrooms;
  int? _bathrooms;
  int? _parkingSpots;
  bool _furnished = false;
  int? _yearBuilt;
  int? _floor;
  int? _totalFloors;

  bool _useMapCoords = false;
  double? _lat;
  double? _lng;

  bool _isAuction = false;
  String? _videoPathOrUrl;
  bool _ownerRequestsPublicName = false;
  bool _usageResidential = false;
  bool _usageCommercial = false;

  /// غلاف القائمة: فيديو أو أول صورة (عند وجود فيديو + صور).
  bool _coverHeroIsVideo = false;

  final Map<String, bool> _amenities = {
    'pool': false,
    'gym': false,
    'elevator': false,
    'security': false,
    'garden': false,
    'balcony': false,
    'ac': false,
    'parking': false,
    'wifi': false,
  };

  final List<_EditImageItem> _items = [];
  final Set<String> _deletedExistingRowIds = {};
  final Set<String> _deletedExistingPaths = {};

  @override
  void initState() {
    super.initState();

    final p = widget.property;

    _title = TextEditingController(text: p.title);
    _desc = TextEditingController(text: p.description);
    _city = TextEditingController(text: p.city);
    _region = TextEditingController(text: p.region ?? '');
    _governorate = TextEditingController(text: p.province ?? '');
    _location = TextEditingController(text: p.location ?? '');
    _buildingNumber = TextEditingController(text: p.buildingNumber ?? '');
    _addressLine = TextEditingController(text: p.addressLine ?? '');
    _deedNumber = TextEditingController(text: p.deedNumber ?? '');
    _deedIssuer = TextEditingController(text: p.deedIssuer ?? '');
    _purpose =
        (p.purpose ?? 'sale').trim().isEmpty ? 'sale' : p.purpose!.trim();
    _deedDate = p.deedDate;
    _price = TextEditingController(text: p.price.toStringAsFixed(0));
    _area = TextEditingController(text: p.area.toStringAsFixed(0));
    _currentBid =
        TextEditingController(text: (p.currentBid ?? 0).toStringAsFixed(0));
    _virtualTourUrl = TextEditingController(text: p.virtualTourUrl ?? '');
    _contactPhone = TextEditingController(text: p.contactPhone ?? '');
    _editReason = TextEditingController();

    _currency = p.currency;
    _negotiable = p.negotiable;
    final rawKey = p.listingTypeKey.trim().toLowerCase();
    _typeCode = rawKey.isNotEmpty ? rawKey : p.type.name.toLowerCase();

    _bedrooms = p.bedrooms;
    _bathrooms = p.bathrooms;
    _parkingSpots = p.parkingSpots;
    _furnished = p.furnished ?? false;
    _yearBuilt = p.yearBuilt;
    _floor = p.floor;
    _totalFloors = p.totalFloors;

    _useMapCoords = p.latitude != null && p.longitude != null;
    _lat = p.latitude;
    _lng = p.longitude;

    _isAuction = p.isAuction;
    _videoPathOrUrl = p.videoUrl;

    _usageResidential = p.usageSuitableResidential;
    _usageCommercial = p.usageSuitableCommercial;
    _ownerRequestsPublicName = p.ownerRequestsPublicName;

    final am = p.amenities ?? <String, bool>{};
    for (final k in _amenities.keys) {
      _amenities[k] = am[k] == true;
    }

    _applyListingGuidance(p.listingGuidance);

    _wireNumericFieldListeners();
    _price.addListener(_onPriceOrAreaChanged);
    _area.addListener(_onPriceOrAreaChanged);
    _bootstrap();
  }

  void _onPriceOrAreaChanged() {
    if (mounted) setState(() {});
  }

  double? _areaInSquareMeters() {
    final raw = _parseNum(_area.text);
    return _areaUnit.toSquareMeters(raw);
  }

  double _areaForSave() {
    final raw = _parseNum(_area.text);
    if (raw <= 0) return 0;
    return _areaInSquareMeters() ?? raw;
  }

  double? _computedPricePerSqm() {
    final p = _parseNum(_price.text);
    final a = _areaInSquareMeters();
    if (p <= 0 || a == null || a <= 0) return null;
    return AppMoney.roundPricePerSqm(p / a);
  }

  void _ensureTypeCodeInCatalog() {
    if (PropertyTypeCatalog.isSelectableTypeSync(_typeCode)) return;
    final fb = Property.parseType(_typeCode).name.toLowerCase();
    if (PropertyTypeCatalog.isSelectableTypeSync(fb)) {
      _typeCode = fb;
      return;
    }
    _typeCode = 'villa';
  }

  void _applyListingGuidance(Map<String, dynamic>? g) {
    if (g == null) return;
    final pb = g['parcel_boundaries'];
    if (pb is Map) {
      final m = pb.cast<String, dynamic>();
      _boundaryNorth.text = (m['north'] ?? '').toString();
      _boundarySouth.text = (m['south'] ?? '').toString();
      _boundaryEast.text = (m['east'] ?? '').toString();
      _boundaryWest.text = (m['west'] ?? '').toString();
    }
    final cp = (g['cover_primary'] ?? 'image').toString().trim().toLowerCase();
    _coverHeroIsVideo = cp == 'video';
  }

  void _wireNumericFieldListeners() {
    void wireDigits(TextEditingController c) {
      c.addListener(() {
        final n = digitsOnly(normalizeAsciiDigits(c.text));
        if (c.text != n) {
          c.value = TextEditingValue(
            text: n,
            selection: TextSelection.collapsed(offset: n.length),
          );
        }
      });
    }

    void wireDecimal(TextEditingController c) {
      c.addListener(() {
        var t = normalizeAsciiDigits(c.text);
        t = t.replaceAll(RegExp(r'[^0-9.]'), '');
        final dot = t.indexOf('.');
        if (dot >= 0) {
          t = t.substring(0, dot + 1) +
              t.substring(dot + 1).replaceAll('.', '');
        }
        if (c.text != t) {
          c.value = TextEditingValue(
            text: t,
            selection: TextSelection.collapsed(offset: t.length),
          );
        }
      });
    }

    wireDecimal(_price);
    wireDecimal(_area);
    wireDecimal(_currentBid);
    wireDigits(_buildingNumber);
    wireDigits(_deedNumber);
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _city.dispose();
    _region.dispose();
    _governorate.dispose();
    _location.dispose();
    _buildingNumber.dispose();
    _addressLine.dispose();
    _deedNumber.dispose();
    _deedIssuer.dispose();
    _parcelNumber.dispose();
    _boundaryNorth.dispose();
    _boundarySouth.dispose();
    _boundaryEast.dispose();
    _boundaryWest.dispose();
    _price.removeListener(_onPriceOrAreaChanged);
    _area.removeListener(_onPriceOrAreaChanged);
    _price.dispose();
    _area.dispose();
    _currentBid.dispose();
    _virtualTourUrl.dispose();
    _contactPhone.dispose();
    _editReason.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await PropertyTypeCustomRegistry.ensureLoaded();
      if (mounted) {
        setState(_ensureTypeCodeInCatalog);
      }
      await Future.wait([
        _loadEditMeta(),
        _loadImages(),
        _loadPropertyExtraFields(),
      ]);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadEditMeta() async {
    final row = await _sb
        .from('properties')
        .select(
          'edit_count, max_edits, edit_exhausted, delete_requested, delete_approved',
        )
        .eq('id', widget.property.id)
        .maybeSingle();

    if (row == null) return;

    if (!mounted) return;
    setState(() {
      _editCount = (row['edit_count'] as num?)?.toInt() ?? 0;
      _maxEdits = (row['max_edits'] as num?)?.toInt() ?? 3;
      _editExhausted = row['edit_exhausted'] == true;
    });
  }

  Future<void> _loadPropertyExtraFields() async {
    try {
      final row = await _sb
          .from('properties')
          .select(
            'governorate,deed_number,deed_date,deed_issuer,building_number,listing_guidance,extra_details',
          )
          .eq('id', widget.property.id)
          .maybeSingle();
      if (row == null || !mounted) return;
      setState(() {
        final g = (row['governorate'] as String?)?.trim();
        if (g != null && g.isNotEmpty) _governorate.text = g;
        final dn = (row['deed_number'] as String?)?.trim();
        if (dn != null && dn.isNotEmpty) _deedNumber.text = dn;
        final di = (row['deed_issuer'] as String?)?.trim();
        if (di != null && di.isNotEmpty) _deedIssuer.text = di;
        final bn = (row['building_number'] as String?)?.trim();
        if (bn != null && bn.isNotEmpty) _buildingNumber.text = bn;
        final dd = row['deed_date'];
        if (dd != null) {
          _deedDate = DateTime.tryParse(dd.toString())?.toLocal();
        }
        final lg = row['listing_guidance'];
        if (lg is Map) {
          _applyListingGuidance(Map<String, dynamic>.from(lg));
        }
        final ed = row['extra_details'];
        if (PropertyTypeCatalog.isLandLikeEffective(_typeCode) && ed is Map) {
          final m = Map<String, dynamic>.from(ed);
          final pn = (m['parcel_number'] ?? '').toString().trim();
          if (pn.isNotEmpty) _parcelNumber.text = pn;
        }
      });
    } catch (_) {}
  }

  bool get _coverChoiceAvailable {
    final hasV = (_videoPathOrUrl ?? '').trim().isNotEmpty;
    final hasI = _items.isNotEmpty;
    return hasV && hasI;
  }

  Map<String, dynamic> _listingGuidancePayloadForSave() {
    final merged = Map<String, dynamic>.from(
      widget.property.listingGuidance ?? {},
    );
    merged['usage'] = {
      'residential': _usageResidential,
      'commercial': _usageCommercial,
    };
    final boundaries = <String, String>{};
    void putB(String k, TextEditingController c) {
      final t = c.text.trim();
      if (t.isNotEmpty) boundaries[k] = t;
    }

    putB('north', _boundaryNorth);
    putB('south', _boundarySouth);
    putB('east', _boundaryEast);
    putB('west', _boundaryWest);
    if (boundaries.isNotEmpty) {
      merged['parcel_boundaries'] = boundaries;
    } else {
      merged.remove('parcel_boundaries');
    }
    final hasV = (_videoPathOrUrl ?? '').trim().isNotEmpty;
    final hasI = _items.isNotEmpty;
    final cover = (!hasV || !hasI)
        ? (hasV ? 'video' : 'image')
        : (_coverHeroIsVideo ? 'video' : 'image');
    merged['cover_primary'] = cover;
    final ppm = _computedPricePerSqm();
    if (ppm != null && ppm > 0) {
      merged['price_per_sqm'] = ppm;
    } else {
      merged.remove('price_per_sqm');
    }
    return merged;
  }

  bool get _editRequiresDeed =>
      const {'sale', 'auction', 'investment'}.contains(_purpose);

  bool get _showBuildingOnEdit =>
      PropertyTypeCatalog.showsBuildingNumber(_typeCode);

  static String _normDeed(String s) => s.replaceAll(RegExp(r'\s+'), '').trim();

  List<Map<String, String>> get _purposeOptions => [
        {'code': 'sale', 'ar': 'بيع', 'en': 'Sale'},
        {'code': 'rent', 'ar': 'إيجار', 'en': 'Rent'},
        {'code': 'daily_rent', 'ar': 'إيجار يومي', 'en': 'Daily Rent'},
        {'code': 'monthly_rent', 'ar': 'إيجار شهري', 'en': 'Monthly Rent'},
        {'code': 'yearly_rent', 'ar': 'إيجار سنوي', 'en': 'Yearly Rent'},
        {'code': 'auction', 'ar': 'مزاد', 'en': 'Auction'},
        {'code': 'investment', 'ar': 'استثمار', 'en': 'Investment'},
      ];

  Future<void> _pickDeedDate() async {
    final picked = await showDeedDateCalendarDialog(
      context: context,
      isAr: _isAr,
      initialDate: _deedDate,
    );
    if (!mounted || picked == null) return;
    setState(() => _deedDate = picked);
  }

  Future<String?> _duplicateDeedBlockingMessage() async {
    const saleP = {'sale', 'auction', 'investment'};
    if (!saleP.contains(_purpose)) return null;
    final d = _normDeed(_deedNumber.text);
    if (d.isEmpty) return null;
    try {
      final res = await _sb
          .from('properties')
          .select('id,title,status,is_auction,deleted_by_user,delete_approved')
          .eq('deed_number', d)
          .neq('id', widget.property.id)
          .limit(40);
      for (final raw in (res as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        if (_rowStillListedForSaleLike(row)) {
          final t = (row['title'] ?? '').toString().trim();
          return _isAr
              ? 'إعلان آخر بنفس رقم الصك ما زال نشطًا للبيع/المزاد/الاستثمار${t.isNotEmpty ? ': $t' : ''}.'
              : 'Another active sale/auction/investment listing uses this deed${t.isNotEmpty ? ': $t' : ''}.';
        }
      }
    } catch (_) {}
    return null;
  }

  bool _rowStillListedForSaleLike(Map<String, dynamic> row) {
    if (row['deleted_by_user'] == true || row['delete_approved'] == true) {
      return false;
    }
    final st = (row['status'] ?? '').toString().toLowerCase();
    const gone = {
      'archived',
      'deleted',
      'inactive',
      'closed',
      'hidden',
      'rejected',
      'cancelled',
      'sold',
      'completed',
      'withdrawn',
    };
    if (gone.contains(st)) return false;
    var purp = (row['purpose'] ?? 'sale').toString().toLowerCase();
    if (purp.isEmpty) purp = 'sale';
    if (row['is_auction'] == true) purp = 'auction';
    return const {'sale', 'auction', 'investment'}.contains(purp);
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? cs.error : null,
        content: Text(
          msg,
          style: TextStyle(color: isError ? cs.onError : null),
        ),
      ),
    );
  }

  double _parseNum(String s) {
    final t = normalizeAsciiDigits(s.trim()).replaceAll(',', '');
    return double.tryParse(t) ?? 0;
  }

  Map<String, dynamic>? _amenitiesPayloadOrNull() {
    final out = <String, bool>{};
    _amenities.forEach((k, v) {
      if (v) out[k] = true;
    });
    return out.isEmpty ? null : out;
  }

  Future<void> _loadImages() async {
    _items.clear();
    _deletedExistingRowIds.clear();
    _deletedExistingPaths.clear();

    final rows = await _sb
        .from('property_images')
        .select('id, path, sort_order')
        .eq('property_id', widget.property.id)
        .order('sort_order', ascending: true);

    for (final r in (rows as List)) {
      final m = Map<String, dynamic>.from(r as Map);
      final id = (m['id'] ?? '').toString();
      final path = (m['path'] ?? '').toString();
      if (id.isEmpty || path.isEmpty) continue;
      _items.add(_EditImageItem.existing(rowId: id, path: path));
    }
  }

  Future<void> _pickImages() async {
    if (_saving || _picking) return;
    if (widget.marketerRegaAlignmentMode) {
      _showSnack(
        _isAr
            ? 'تعديل الصور يتم من حساب المالك فقط.'
            : 'Image changes are managed by the owner only.',
        isError: true,
      );
      return;
    }

    if (_isGuest) {
      _showSnack(
        _isAr
            ? 'يجب تسجيل الدخول لتعديل الصور'
            : 'You must log in to edit images',
        isError: true,
      );
      return;
    }

    if (_uid != widget.property.ownerId) {
      _showSnack(
        _isAr ? 'لا تملك صلاحية تعديل هذا الإعلان' : 'Not allowed',
        isError: true,
      );
      return;
    }

    final nativeMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final t = AppLocalizations.of(context);
    if (nativeMobile && t != null) {
      final ok = await RuntimePermissionHelper.ensurePhotos(context, t: t);
      if (!ok || !mounted) return;
    }

    setState(() => _picking = true);
    suspendAutoLock.value = true;

    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.image,
        withData: true,
      );

      if (!mounted || res == null) return;

      final newOnes = res.files
          .where((f) => f.bytes != null && f.name.isNotEmpty)
          .map((f) => _EditImageItem.newOne(name: f.name, bytes: f.bytes!))
          .toList();

      if (newOnes.isEmpty) return;

      setState(() => _items.addAll(newOnes));
    } catch (e) {
      if (mounted) {
        _showSnack(
          _isAr ? 'فشل اختيار الصور: $e' : 'Pick images failed: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
      suspendAutoLock.value = false;
    }
  }

  void _removeAt(int index) {
    if (widget.marketerRegaAlignmentMode) {
      _showSnack(
        _isAr
            ? 'لا يمكن حذف الصور في وضع مطابقة الهيئة.'
            : 'Removing images is not available in REGA alignment mode.',
        isError: true,
      );
      return;
    }
    final it = _items[index];
    setState(() {
      _items.removeAt(index);
      if (it.isExisting) {
        _deletedExistingRowIds.add(it.rowId!);
        _deletedExistingPaths.add(it.path!);
      }
    });
  }

  void _move(int from, int to) {
    if (from == to) return;
    setState(() {
      final item = _items.removeAt(from);
      _items.insert(to, item);
    });
  }

  String _imgPublicUrl(String path) =>
      _sb.storage.from('property-images').getPublicUrl(path);

  Future<void> _pickAndUploadVideo() async {
    if (_saving || _picking || _uploadingVideo) return;

    if (_isGuest) {
      _showSnack(_isAr ? 'سجّل الدخول أولاً' : 'Login first', isError: true);
      return;
    }

    if (_uid != widget.property.ownerId) {
      _showSnack(_isAr ? 'لا تملك صلاحية' : 'Not allowed', isError: true);
      return;
    }

    setState(() => _uploadingVideo = true);
    suspendAutoLock.value = true;

    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.video,
        withData: true,
      );

      if (!mounted || res == null || res.files.isEmpty) return;

      final f = res.files.first;
      final bytes = f.bytes;
      if (bytes == null) {
        _showSnack(
          _isAr ? 'تعذر قراءة الفيديو' : 'Failed to read video',
          isError: true,
        );
        return;
      }

      final uuid = const Uuid().v4();
      final ext = (f.extension ?? 'mp4').toLowerCase();
      final path = '${_uid.trim()}/$uuid.$ext';

      await _sb.storage.from('property-videos').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _guessVideoMime(ext),
            ),
          );

      setState(() => _videoPathOrUrl = path);
      _showSnack(_isAr ? 'تم رفع الفيديو' : 'Video uploaded');
    } catch (e) {
      _showSnack(
        _isAr ? 'فشل رفع الفيديو: $e' : 'Upload failed: $e',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
      suspendAutoLock.value = false;
    }
  }

  String _guessVideoMime(String ext) {
    switch (ext) {
      case 'mov':
        return 'video/quicktime';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'mp4':
      default:
        return 'video/mp4';
    }
  }

  String _limitMessage() {
    return _isAr
        ? 'لقد استنفدت جميع التعديلات المسموحة لهذا العقار. التعديلات المستقبلية ستكون عبر اشتراك.'
        : 'You have used all allowed edits for this property. Future edits will require a subscription.';
  }

  Future<Property> _fetchUpdatedProperty() async {
    final data = await _sb
        .from('properties')
        .select(SupabaseSchemaSelects.propertiesListing)
        .eq('id', widget.property.id)
        .single();

    return Property.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> _save() async {
    if (_saving) return;

    if (_isGuest) {
      _showSnack(
        _isAr ? 'يجب تسجيل الدخول للتعديل' : 'You must log in to edit',
        isError: true,
      );
      return;
    }

    if (widget.marketerRegaAlignmentMode) {
      if (!ListingEditPermissions.marketerMayAlignWithRega(
        widget.property,
        _uid,
      )) {
        _showSnack(
          _isAr
              ? 'لا يمكن حفظ التعديل في هذه المرحلة.'
              : 'Cannot save changes at this stage.',
          isError: true,
        );
        return;
      }

      final ok = _formKey.currentState?.validate() ?? false;
      if (!ok) return;

      if (_items.isEmpty) {
        _showSnack(
          _isAr
              ? 'يجب أن يحتفظ الإعلان بصورة واحدة على الأقل'
              : 'The listing must keep at least one image',
          isError: true,
        );
        return;
      }

      if (!_usageResidential && !_usageCommercial) {
        _showSnack(
          _isAr
              ? 'حدد سكني و/أو تجاري في «استخدام العقار»'
              : 'Select residential and/or commercial under property use',
          isError: true,
        );
        return;
      }

      setState(() {
        _saving = true;
        _error = null;
      });

      try {
        final dn = _normDeed(_deedNumber.text);
        await _sb.from('properties').update({
          'title': _title.text.trim(),
          'description': _desc.text.trim(),
          'city': _city.text.trim(),
          'region': _region.text.trim().isEmpty ? null : _region.text.trim(),
          'governorate': _governorate.text.trim().isEmpty
              ? null
              : _governorate.text.trim(),
          'location':
              _location.text.trim().isEmpty ? null : _location.text.trim(),
          'address_line': _addressLine.text.trim().isEmpty
              ? null
              : _addressLine.text.trim(),
          'building_number': _buildingNumber.text.trim().isEmpty
              ? null
              : _buildingNumber.text.trim(),
          'deed_number': dn.isEmpty ? null : dn,
          'deed_date': _deedDate == null
              ? null
              : DateTime(_deedDate!.year, _deedDate!.month, _deedDate!.day)
                  .toIso8601String()
                  .substring(0, 10),
          'deed_issuer':
              _deedIssuer.text.trim().isEmpty ? null : _deedIssuer.text.trim(),
          'listing_guidance': _listingGuidancePayloadForSave(),
        }).eq('id', widget.property.id);

        final updatedProperty = await _fetchUpdatedProperty();
        if (!mounted) return;
        _showSnack(
          _isAr ? 'تم حفظ مطابقة الهيئة' : 'REGA alignment saved',
        );
        Navigator.pop(context, updatedProperty);
      } on PostgrestException catch (e) {
        if (!mounted) return;
        setState(() => _error = e.message);
        _showSnack(
          _isAr ? 'فشل الحفظ: ${e.message}' : 'Save failed: ${e.message}',
          isError: true,
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = e.toString());
        _showSnack(
          _isAr ? 'فشل الحفظ: $e' : 'Save failed: $e',
          isError: true,
        );
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    if (_uid != widget.property.ownerId) {
      _showSnack(
        _isAr ? 'لا تملك صلاحية تعديل هذا الإعلان' : 'Not allowed',
        isError: true,
      );
      return;
    }

    if (_editExhausted || _editCount >= _maxEdits) {
      _showSnack(_limitMessage(), isError: true);
      return;
    }

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    if (_items.isEmpty) {
      _showSnack(
        _isAr
            ? 'يجب وجود صورة واحدة على الأقل'
            : 'At least one image is required',
        isError: true,
      );
      return;
    }

    if (!_usageResidential && !_usageCommercial) {
      _showSnack(
        _isAr
            ? 'حدد سكني و/أو تجاري في «استخدام العقار»'
            : 'Select residential and/or commercial under property use',
        isError: true,
      );
      return;
    }

    final reason = _editReason.text.trim();
    if (reason.isEmpty) {
      _showSnack(
        _isAr ? 'يجب كتابة سبب التعديل' : 'Edit reason is required',
        isError: true,
      );
      return;
    }

    if (_editRequiresDeed) {
      if (_normDeed(_deedNumber.text).isEmpty) {
        _showSnack(
          _isAr ? 'رقم الصك مطلوب لهذا الغرض' : 'Deed number is required',
          isError: true,
        );
        return;
      }
      if (_deedDate == null) {
        _showSnack(
          _isAr ? 'تاريخ الصك مطلوب' : 'Deed date is required',
          isError: true,
        );
        return;
      }
      if (_deedIssuer.text.trim().isEmpty) {
        _showSnack(
          _isAr ? 'الجهة المصدرة مطلوبة' : 'Deed issuer is required',
          isError: true,
        );
        return;
      }
    }

    final dupMsg = await _duplicateDeedBlockingMessage();
    if (dupMsg != null) {
      if (!mounted) return;
      _showSnack(dupMsg, isError: true);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_isAr ? 'تنبيه' : 'Notice'),
          content: Text(dupMsg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_isAr ? 'حسنًا' : 'OK'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final imgBucket = _sb.storage.from('property-images');
    final uuid = const Uuid();

    try {
      await _sb.rpc(
        'owner_edit_property',
        params: {
          'p_property_id': widget.property.id,
          'p_title': _title.text.trim(),
          'p_description': _desc.text.trim(),
          'p_city': _city.text.trim(),
          'p_region': _region.text.trim(),
          'p_location':
              _location.text.trim().isEmpty ? null : _location.text.trim(),
          'p_address_line': _addressLine.text.trim().isEmpty
              ? null
              : _addressLine.text.trim(),
          'p_type': _typeCode,
          'p_price': _parseNum(_price.text),
          'p_area': _areaForSave(),
          'p_currency': _currency,
          'p_negotiable': _negotiable,
          'p_bedrooms':
              PropertyTypeCatalog.showsResidentialRoomBedCountsEffective(
                      _typeCode)
                  ? _bedrooms
                  : null,
          'p_bathrooms':
              PropertyTypeCatalog.showsResidentialRoomBedCountsEffective(
                      _typeCode)
                  ? _bathrooms
                  : null,
          'p_parking_spots':
              PropertyTypeCatalog.showsParkingYearRowEffective(_typeCode)
                  ? _parkingSpots
                  : null,
          'p_furnished':
              PropertyTypeCatalog.showsFurnishedRowEffective(_typeCode)
                  ? _furnished
                  : null,
          'p_year_built':
              PropertyTypeCatalog.showsParkingYearRowEffective(_typeCode)
                  ? _yearBuilt
                  : null,
          'p_floor': PropertyTypeCatalog.showsFloorFieldsEffective(_typeCode)
              ? _floor
              : null,
          'p_total_floors':
              PropertyTypeCatalog.showsFloorFieldsEffective(_typeCode)
                  ? _totalFloors
                  : null,
          'p_is_auction': _isAuction,
          'p_current_bid': _isAuction ? _parseNum(_currentBid.text) : null,
          'p_amenities': _amenitiesPayloadOrNull(),
          'p_latitude': _useMapCoords ? _lat : null,
          'p_longitude': _useMapCoords ? _lng : null,
          'p_video_url': (_videoPathOrUrl ?? '').trim().isEmpty
              ? null
              : _videoPathOrUrl!.trim(),
          'p_virtual_tour_url': _virtualTourUrl.text.trim().isEmpty
              ? null
              : _virtualTourUrl.text.trim(),
          'p_contact_phone': null,
          'p_reason': reason,
        },
      );

      try {
        final dn = _normDeed(_deedNumber.text);
        await _sb
            .from('properties')
            .update({
              'governorate': _governorate.text.trim().isEmpty
                  ? null
                  : _governorate.text.trim(),
              'deed_number': dn.isEmpty ? null : dn,
              'deed_date': _deedDate == null
                  ? null
                  : DateTime(_deedDate!.year, _deedDate!.month, _deedDate!.day)
                      .toIso8601String()
                      .substring(0, 10),
              'deed_issuer': _deedIssuer.text.trim().isEmpty
                  ? null
                  : _deedIssuer.text.trim(),
              'building_number': _buildingNumber.text.trim().isEmpty
                  ? null
                  : _buildingNumber.text.trim(),
            })
            .eq('id', widget.property.id)
            .eq('owner_id', _uid);
      } catch (_) {}

      try {
        await _sb
            .from('properties')
            .update({
              'owner_requests_public_name': _ownerRequestsPublicName,
            })
            .eq('id', widget.property.id)
            .eq('owner_id', _uid);
      } catch (_) {}

      try {
        await _sb
            .from('properties')
            .update({
              'listing_guidance': _listingGuidancePayloadForSave(),
              'contact_phone': null,
            })
            .eq('id', widget.property.id)
            .eq('owner_id', _uid);
      } catch (_) {}

      try {
        const landExtraKeys = <String>{
          'parcel_number',
          'land_use',
          'facade',
          'street_count',
          'street_widths',
          'is_corner',
          'plan_number',
        };
        final cur = await _sb
            .from('properties')
            .select('extra_details')
            .eq('id', widget.property.id)
            .maybeSingle();
        final ed = <String, dynamic>{};
        if (cur != null && cur['extra_details'] is Map) {
          ed.addAll(Map<String, dynamic>.from(cur['extra_details'] as Map));
        }
        if (PropertyTypeCatalog.isLandLikeEffective(_typeCode)) {
          final pn = _parcelNumber.text.trim();
          if (pn.isNotEmpty) {
            ed['parcel_number'] = pn;
          } else {
            ed.remove('parcel_number');
          }
        } else {
          for (final k in landExtraKeys) {
            ed.remove(k);
          }
        }
        await _sb
            .from('properties')
            .update({
              'extra_details': ed,
            })
            .eq('id', widget.property.id)
            .eq('owner_id', _uid);
      } catch (_) {}

      if (_deletedExistingRowIds.isNotEmpty) {
        await _sb
            .from('property_images')
            .delete()
            .inFilter('id', _deletedExistingRowIds.toList());
      }

      if (_deletedExistingPaths.isNotEmpty) {
        try {
          await imgBucket.remove(_deletedExistingPaths.toList());
        } catch (_) {}
      }

      for (final it in _items.where((x) => x.isNew).toList()) {
        final path = '${_uid.trim()}/${uuid.v4()}.jpg';

        Uint8List bytesToUpload = it.bytes!;
        try {
          bytesToUpload = await WatermarkService.addTextWatermark(
            bytesToUpload,
            text: '© موثوق العقاري | Motawoq Real Estate',
          );
        } catch (_) {}

        await imgBucket.uploadBinary(
          path,
          bytesToUpload,
          fileOptions: const FileOptions(
            upsert: false,
            contentType: 'image/jpeg',
          ),
        );

        final inserted = await _sb
            .from('property_images')
            .insert({
              'property_id': widget.property.id,
              'path': path,
              'sort_order': 0,
              'uploaded_by': _uid,
            })
            .select('id')
            .single();

        final newRowId = (inserted['id'] ?? '').toString();
        final idx = _items.indexOf(it);
        if (idx >= 0) {
          _items[idx] = _EditImageItem.existing(rowId: newRowId, path: path);
        }
      }

      for (int i = 0; i < _items.length; i++) {
        final it = _items[i];
        if (!it.isExisting || (it.rowId ?? '').isEmpty) continue;
        await _sb
            .from('property_images')
            .update({'sort_order': i}).eq('id', it.rowId!);
      }

      await _loadEditMeta();
      final updatedProperty = await _fetchUpdatedProperty();

      if (!mounted) return;

      final exhaustedNow = _editExhausted || _editCount >= _maxEdits;

      if (exhaustedNow) {
        _showSnack(
          _isAr
              ? 'تم حفظ آخر تعديل مسموح لهذا العقار. التعديلات القادمة ستكون باشتراك.'
              : 'Your final allowed edit has been saved. Future edits will require a subscription.',
        );
      } else {
        _showSnack(
          _isAr
              ? 'تم حفظ التعديلات بنجاح (${_editCount}/$_maxEdits)'
              : 'Changes saved successfully ($_editCount/$_maxEdits)',
        );
      }

      Navigator.pop(context, updatedProperty);
    } on PostgrestException catch (e) {
      final msg = e.message.toUpperCase();

      if (msg.contains('EDIT_LIMIT_REACHED')) {
        setState(() {
          _editExhausted = true;
          _editCount = _maxEdits;
        });
        _showSnack(_limitMessage(), isError: true);
      } else {
        setState(() => _error = e.message);
        _showSnack(
          _isAr
              ? 'فشل حفظ التعديلات: ${e.message}'
              : 'Save failed: ${e.message}',
          isError: true,
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
      _showSnack(
        _isAr ? 'فشل حفظ التعديلات: $e' : 'Save failed: $e',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildEditsInfoCard() {
    final cs = Theme.of(context).colorScheme;
    final remaining = (_maxEdits - _editCount).clamp(0, _maxEdits);
    final exhausted = _editExhausted || _editCount >= _maxEdits;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: exhausted
            ? cs.errorContainer.withOpacity(0.70)
            : cs.primaryContainer.withOpacity(0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: exhausted
              ? cs.error.withOpacity(0.25)
              : const Color(0xFF0F766E).withOpacity(0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            exhausted ? Icons.block_outlined : Icons.edit_note_outlined,
            color: exhausted ? cs.error : const Color(0xFF0F766E),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exhausted
                      ? (_isAr ? 'انتهى حد التعديلات' : 'Edit limit reached')
                      : (_isAr ? 'التعديلات المتاحة' : 'Available edits'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  exhausted
                      ? _limitMessage()
                      : (_isAr
                          ? 'استهلكت $_editCount من أصل $_maxEdits. المتبقي: $remaining.'
                          : 'You used $_editCount of $_maxEdits. Remaining: $remaining.'),
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final exhausted = _editExhausted || _editCount >= _maxEdits;

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: Text(
            widget.marketerRegaAlignmentMode
                ? (_isAr ? 'مطابقة بيانات الهيئة' : 'REGA alignment')
                : (_isAr ? 'تعديل الإعلان' : 'Edit listing'),
          ),
          actions: [
            IconButton(
              icon: _saving
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: AppLogoLoading(compact: true, size: 20),
                    )
                  : const Icon(Icons.save),
              onPressed:
                  (_saving || (!widget.marketerRegaAlignmentMode && exhausted))
                      ? null
                      : _save,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: AppLogoLoading())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!widget.marketerRegaAlignmentMode) ...[
                    _buildEditsInfoCard(),
                    const SizedBox(height: 12),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF0F766E).withOpacity(0.25),
                        ),
                      ),
                      child: Text(
                        _isAr
                            ? 'وضع المسوّق: عدّل الحقول التي تطلبها بيانات الهيئة (النص، الموقع، الصك…). الصور من حساب المالك.'
                            : 'Marketer mode: adjust fields required to match REGA (text, location, deed…). Images stay with the owner.',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: cs.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: cs.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (!widget.marketerRegaAlignmentMode) ...[
                            _secTitle(_isAr ? 'سبب التعديل' : 'Edit reason'),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _editReason,
                              enabled: !_saving && !exhausted,
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText: _isAr
                                    ? 'سبب التعديل *'
                                    : 'Reason for edit *',
                                helperText: _isAr
                                    ? 'يتم حفظ السبب ضمن سجل التعديلات'
                                    : 'This reason is saved in the edit history',
                              ),
                              validator: (v) {
                                final s = (v ?? '').trim();
                                if (s.isEmpty) {
                                  return _isAr
                                      ? 'سبب التعديل مطلوب'
                                      : 'Edit reason is required';
                                }
                                if (s.length < 5) {
                                  return _isAr
                                      ? 'اكتب سببًا أوضح'
                                      : 'Please enter a clearer reason';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                          ],
                          _secTitle(_isAr ? 'بيانات الإعلان' : 'Listing info'),
                          const SizedBox(height: 10),
                          PropertyTypeHierarchyPicker(
                            value: PropertyTypeCatalog.isSelectableTypeSync(
                                    _typeCode)
                                ? _typeCode
                                : PropertyTypeCatalog.entries.first['code']!,
                            isAr: _isAr,
                            saving: _saving || exhausted,
                            onChanged: (v) {
                              setState(() {
                                final wasLand =
                                    PropertyTypeCatalog.isLandLikeEffective(
                                        _typeCode);
                                _typeCode = v;
                                final nowLand =
                                    PropertyTypeCatalog.isLandLikeEffective(
                                        _typeCode);
                                if (wasLand && !nowLand) {
                                  _parcelNumber.clear();
                                  _boundaryNorth.clear();
                                  _boundarySouth.clear();
                                  _boundaryEast.clear();
                                  _boundaryWest.clear();
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          _secTitle(_isAr ? 'استخدام العقار' : 'Property use'),
                          const SizedBox(height: 6),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _usageResidential,
                            onChanged: (_saving || exhausted)
                                ? null
                                : (v) => setState(
                                      () => _usageResidential = v ?? false,
                                    ),
                            title: Text(_isAr ? 'سكني' : 'Residential'),
                            secondary: const Icon(Icons.home_work_outlined),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _usageCommercial,
                            onChanged: (_saving || exhausted)
                                ? null
                                : (v) => setState(
                                      () => _usageCommercial = v ?? false,
                                    ),
                            title: Text(_isAr ? 'تجاري' : 'Commercial'),
                            secondary: const Icon(Icons.storefront_outlined),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _purposeOptions
                                    .any((e) => e['code'] == _purpose)
                                ? _purpose
                                : 'sale',
                            items: _purposeOptions
                                .map(
                                  (e) => DropdownMenuItem<String>(
                                    value: e['code'],
                                    child: Text(
                                      _isAr ? (e['ar'] ?? '') : (e['en'] ?? ''),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (_saving || exhausted)
                                ? null
                                : (v) => setState(() => _purpose = v ?? 'sale'),
                            decoration: InputDecoration(
                              labelText: _isAr ? 'الغرض' : 'Purpose',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _title,
                            enabled: !_saving && !exhausted,
                            decoration: InputDecoration(
                              labelText: _isAr ? 'عنوان الإعلان *' : 'Title *',
                            ),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) {
                                return _isAr
                                    ? 'العنوان مطلوب'
                                    : 'Title is required';
                              }
                              if (s.length < 3) {
                                return _isAr
                                    ? 'العنوان قصير'
                                    : 'Title is too short';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: _isAr
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Text(
                              _isAr ? 'مدن سريعة' : 'Quick cities',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                List.generate(_kEditQuickCityAr.length, (i) {
                              final ar = _kEditQuickCityAr[i];
                              final label = _isAr
                                  ? _kEditQuickCityAr[i]
                                  : _kEditQuickCityEn[i];
                              return ChoiceChip(
                                showCheckmark: false,
                                label: Text(label),
                                selected: _city.text.trim() == ar,
                                onSelected: (_saving || exhausted)
                                    ? null
                                    : (_) => setState(() => _city.text = ar),
                              );
                            }),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _city,
                            enabled: !_saving && !exhausted,
                            decoration: InputDecoration(
                              labelText: _isAr ? 'المدينة *' : 'City *',
                            ),
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? (_isAr
                                    ? 'المدينة مطلوبة'
                                    : 'City is required')
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _region,
                            enabled: !_saving && !exhausted,
                            decoration: InputDecoration(
                              labelText: _isAr ? 'المنطقة' : 'Region',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _governorate,
                            enabled: !_saving && !exhausted,
                            decoration: InputDecoration(
                              labelText: _isAr ? 'المحافظة' : 'Governorate',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _location,
                            enabled: !_saving && !exhausted,
                            decoration: InputDecoration(
                              labelText:
                                  _isAr ? 'الحي (يدوي)' : 'District (manual)',
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (PropertyTypeCatalog.isLandLikeEffective(
                              _typeCode)) ...[
                            _secTitle(_isAr
                                ? 'القطعة والحدود'
                                : 'Parcel & boundaries'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _parcelNumber,
                              enabled: !_saving && !exhausted,
                              decoration: InputDecoration(
                                labelText:
                                    _isAr ? 'رقم القطعة' : 'Parcel number',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _boundaryNorth,
                              enabled: !_saving && !exhausted,
                              decoration: InputDecoration(
                                labelText:
                                    _isAr ? 'حد شمالي' : 'North boundary',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _boundarySouth,
                              enabled: !_saving && !exhausted,
                              decoration: InputDecoration(
                                labelText:
                                    _isAr ? 'حد جنوبي' : 'South boundary',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _boundaryEast,
                              enabled: !_saving && !exhausted,
                              decoration: InputDecoration(
                                labelText: _isAr ? 'حد شرقي' : 'East boundary',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _boundaryWest,
                              enabled: !_saving && !exhausted,
                              decoration: InputDecoration(
                                labelText: _isAr ? 'حد غربي' : 'West boundary',
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_showBuildingOnEdit) ...[
                            TextFormField(
                              controller: _buildingNumber,
                              enabled: !_saving && !exhausted,
                              decoration: InputDecoration(
                                labelText:
                                    _isAr ? 'رقم المبنى' : 'Building number',
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _addressLine,
                            enabled: !_saving && !exhausted,
                            decoration: InputDecoration(
                              labelText:
                                  _isAr ? 'العنوان الوطني' : 'National address',
                            ),
                          ),
                          const SizedBox(height: 12),
                          _secTitle(_isAr ? 'بيانات الصك' : 'Deed'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _deedNumber,
                            enabled: !_saving && !exhausted,
                            decoration: InputDecoration(
                              labelText: _isAr ? 'رقم الصك' : 'Deed number',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _deedDate == null
                                      ? (_isAr
                                          ? 'تاريخ الصك: غير محدد'
                                          : 'Deed date: not set')
                                      : (_isAr
                                          ? 'تاريخ الصك: ${_deedDate!.year}-${_deedDate!.month.toString().padLeft(2, '0')}-${_deedDate!.day.toString().padLeft(2, '0')}'
                                          : 'Deed date: ${_deedDate!.year}-${_deedDate!.month.toString().padLeft(2, '0')}-${_deedDate!.day.toString().padLeft(2, '0')}'),
                                ),
                              ),
                              TextButton(
                                onPressed: (_saving || exhausted)
                                    ? null
                                    : _pickDeedDate,
                                child: Text(_isAr ? 'اختيار' : 'Pick'),
                              ),
                              if (_deedDate != null)
                                TextButton(
                                  onPressed: (_saving || exhausted)
                                      ? null
                                      : () => setState(() => _deedDate = null),
                                  child: Text(_isAr ? 'مسح' : 'Clear'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _deedIssuer,
                            enabled: !_saving && !exhausted,
                            decoration: InputDecoration(
                              labelText: _isAr
                                  ? 'الجهة المصدرة للصك'
                                  : 'Issuing authority',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _desc,
                            enabled: !_saving && !exhausted,
                            maxLines: 4,
                            decoration: InputDecoration(
                              labelText: _isAr ? 'الوصف *' : 'Description *',
                            ),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) {
                                return _isAr
                                    ? 'الوصف مطلوب'
                                    : 'Description is required';
                              }
                              if (s.length < 10) {
                                return _isAr
                                    ? 'الوصف قصير'
                                    : 'Description too short';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          _secTitle(_isAr ? 'السعر والمساحة' : 'Price & Area'),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _price,
                                  enabled: !_saving && !exhausted,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  inputFormatters:
                                      latinDecimalNumberFormatters(),
                                  decoration: InputDecoration(
                                    labelText: _isAr ? 'السعر *' : 'Price *',
                                  ),
                                  validator: (v) => _parseNum(v ?? '') <= 0
                                      ? (_isAr
                                          ? 'سعر غير صحيح'
                                          : 'Invalid price')
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 140,
                                child: DropdownButtonFormField<String>(
                                  value: _currency,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'SAR',
                                      child: Text('SAR'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'USD',
                                      child: Text('USD'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'EUR',
                                      child: Text('EUR'),
                                    ),
                                  ],
                                  onChanged: (_saving || exhausted)
                                      ? null
                                      : (v) => setState(
                                          () => _currency = v ?? _currency),
                                  decoration: InputDecoration(
                                    labelText: _isAr ? 'العملة' : 'Currency',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _area,
                                  enabled: !_saving && !exhausted,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  inputFormatters:
                                      latinDecimalNumberFormatters(),
                                  decoration: InputDecoration(
                                    labelText: _isAr ? 'المساحة *' : 'Area *',
                                  ),
                                  validator: (v) => _parseNum(v ?? '') <= 0
                                      ? (_isAr
                                          ? 'مساحة غير صحيحة'
                                          : 'Invalid area')
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 120,
                                child: DropdownButtonFormField<ListingAreaUnit>(
                                  value: _areaUnit,
                                  items: [
                                    DropdownMenuItem(
                                      value: ListingAreaUnit.m2,
                                      child: Text(_isAr ? 'م²' : 'm²'),
                                    ),
                                    DropdownMenuItem(
                                      value: ListingAreaUnit.cm2,
                                      child: Text(_isAr ? 'سم²' : 'cm²'),
                                    ),
                                  ],
                                  onChanged: (_saving || exhausted)
                                      ? null
                                      : (v) => setState(
                                            () => _areaUnit =
                                                v ?? ListingAreaUnit.m2,
                                          ),
                                  decoration: InputDecoration(
                                    labelText:
                                        _isAr ? 'وحدة المساحة' : 'Area unit',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Builder(
                            builder: (context) {
                              final ppm = _computedPricePerSqm();
                              final cs = Theme.of(context).colorScheme;
                              final st = TextStyle(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurfaceVariant,
                              );
                              return InputDecorator(
                                decoration: InputDecoration(
                                  labelText:
                                      _isAr ? 'سعر المتر (م²)' : 'Price per m²',
                                  border: const OutlineInputBorder(),
                                ),
                                child: ppm == null
                                    ? Text('—', style: st)
                                    : AppMoneyLine(
                                        amount: ppm,
                                        currencyCode: _currency,
                                        isAr: _isAr,
                                        style: st,
                                      ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          SwitchListTile(
                            value: _negotiable,
                            onChanged: (_saving || exhausted)
                                ? null
                                : (v) => setState(() => _negotiable = v),
                            contentPadding: EdgeInsets.zero,
                            title: Text(_isAr ? 'قابل للتفاوض' : 'Negotiable'),
                          ),
                          SwitchListTile(
                            value: _ownerRequestsPublicName,
                            onChanged: (_saving || exhausted)
                                ? null
                                : (v) => setState(
                                      () => _ownerRequestsPublicName = v,
                                    ),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _isAr
                                  ? 'أطلب إظهار اسمي على الإعلان للجميع'
                                  : 'Request my name shown to everyone',
                            ),
                            subtitle: Text(
                              _isAr
                                  ? 'يُفضّل مع موافقة المسوق؛ يُستخدم إن اختار إخفاء اسم المالك.'
                                  : 'Applies if the marketer hides the owner name.',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _secTitle(_isAr ? 'التفاصيل' : 'Details'),
                          const SizedBox(height: 10),
                          if (PropertyTypeCatalog
                              .showsResidentialRoomBedCountsEffective(
                                  _typeCode)) ...[
                            _numDrop(
                              label: _isAr ? 'غرف النوم' : 'Bedrooms',
                              value: _bedrooms,
                              min: 0,
                              max: 20,
                              onChanged: (v) => setState(() => _bedrooms = v),
                              disabled: _saving || exhausted,
                            ),
                            const SizedBox(height: 10),
                            _numDrop(
                              label: _isAr ? 'دورات المياه' : 'Bathrooms',
                              value: _bathrooms,
                              min: 0,
                              max: 20,
                              onChanged: (v) => setState(() => _bathrooms = v),
                              disabled: _saving || exhausted,
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (PropertyTypeCatalog.showsParkingYearRowEffective(
                              _typeCode)) ...[
                            _numDrop(
                              label: _isAr ? 'مواقف' : 'Parking spots',
                              value: _parkingSpots,
                              min: 0,
                              max: 50,
                              onChanged: (v) =>
                                  setState(() => _parkingSpots = v),
                              disabled: _saving || exhausted,
                            ),
                            const SizedBox(height: 10),
                            YearBuiltPickerField(
                              value: _yearBuilt,
                              onChanged: (v) => setState(() => _yearBuilt = v),
                              enabled: !_saving && !exhausted,
                              isAr: _isAr,
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (PropertyTypeCatalog.showsFurnishedRowEffective(
                              _typeCode)) ...[
                            SwitchListTile(
                              value: _furnished,
                              onChanged: (_saving || exhausted)
                                  ? null
                                  : (v) => setState(() => _furnished = v),
                              contentPadding: EdgeInsets.zero,
                              title: Text(_isAr ? 'مفروش' : 'Furnished'),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (PropertyTypeCatalog.showsFloorFieldsEffective(
                              _typeCode)) ...[
                            _numDrop(
                              label: _isAr ? 'الدور' : 'Floor',
                              value: _floor,
                              min: 0,
                              max: 200,
                              onChanged: (v) => setState(() => _floor = v),
                              disabled: _saving || exhausted,
                            ),
                            const SizedBox(height: 10),
                            _numDrop(
                              label: _isAr ? 'عدد الأدوار' : 'Total floors',
                              value: _totalFloors,
                              min: 0,
                              max: 200,
                              onChanged: (v) =>
                                  setState(() => _totalFloors = v),
                              disabled: _saving || exhausted,
                            ),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 16),
                          _secTitle(_isAr ? 'المرافق' : 'Amenities'),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _amenities.keys
                                .where((k) =>
                                    !PropertyTypeCatalog.isLandLikeEffective(
                                        _typeCode) ||
                                    PropertyTypeCatalog
                                        .amenityKeyRelevantForLand(k))
                                .map((k) {
                              final label = _amenityLabel(k);
                              final sel = _amenities[k] == true;
                              return FilterChip(
                                selected: sel,
                                showCheckmark: true,
                                label: Text(label),
                                onSelected: (_saving || exhausted)
                                    ? null
                                    : (v) => setState(() => _amenities[k] = v),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          _secTitle(_isAr ? 'الإحداثيات' : 'Coordinates'),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            value: _useMapCoords,
                            onChanged: (_saving || exhausted)
                                ? null
                                : (v) => setState(() => _useMapCoords = v),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _isAr ? 'تفعيل الإحداثيات' : 'Enable coordinates',
                            ),
                          ),
                          if (_useMapCoords) ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              enabled: !_saving && !exhausted,
                              initialValue: _lat?.toString() ?? '',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: latinDecimalNumberFormatters(),
                              decoration: const InputDecoration(
                                labelText: 'Lat',
                              ),
                              onChanged: (v) =>
                                  _lat = double.tryParse(v.trim()),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              enabled: !_saving && !exhausted,
                              initialValue: _lng?.toString() ?? '',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: latinDecimalNumberFormatters(),
                              decoration: const InputDecoration(
                                labelText: 'Lng',
                              ),
                              onChanged: (v) =>
                                  _lng = double.tryParse(v.trim()),
                            ),
                          ],
                          const SizedBox(height: 16),
                          _secTitle(_isAr ? 'المزاد' : 'Auction'),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            value: _isAuction,
                            onChanged: (_saving || exhausted)
                                ? null
                                : (v) => setState(() => _isAuction = v),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _isAr
                                  ? 'هذا الإعلان مزاد'
                                  : 'This is an auction listing',
                            ),
                          ),
                          if (_isAuction) ...[
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _currentBid,
                              enabled: !_saving && !exhausted,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: latinDecimalNumberFormatters(),
                              decoration: InputDecoration(
                                labelText:
                                    _isAr ? 'السعر الحالي' : 'Current bid',
                              ),
                              validator: (v) => _parseNum(v ?? '') <= 0
                                  ? (_isAr ? 'سعر غير صحيح' : 'Invalid')
                                  : null,
                            ),
                          ],
                          const SizedBox(height: 16),
                          _secTitle(_isAr ? 'روابط/فيديو' : 'Links/Video'),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _virtualTourUrl,
                            enabled: !_saving && !exhausted,
                            decoration: InputDecoration(
                              labelText: _isAr
                                  ? 'رابط جولة افتراضية'
                                  : 'Virtual tour URL',
                            ),
                            keyboardType: TextInputType.url,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (_videoPathOrUrl ?? '').trim().isEmpty
                                      ? (_isAr ? 'لا يوجد فيديو' : 'No video')
                                      : (_isAr
                                          ? 'موجود فيديو'
                                          : 'Video attached'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed:
                                    (_saving || _uploadingVideo || exhausted)
                                        ? null
                                        : _pickAndUploadVideo,
                                icon: _uploadingVideo
                                    ? SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: AppLogoLoading(
                                          compact: true,
                                          size: 20,
                                        ),
                                      )
                                    : const Icon(Icons.video_file_outlined),
                                label:
                                    Text(_isAr ? 'رفع فيديو' : 'Upload video'),
                              ),
                              if ((_videoPathOrUrl ?? '').trim().isNotEmpty)
                                IconButton(
                                  tooltip:
                                      _isAr ? 'حذف الفيديو' : 'Remove video',
                                  onPressed: (_saving || exhausted)
                                      ? null
                                      : () => setState(
                                          () => _videoPathOrUrl = null),
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: cs.error,
                                  ),
                                ),
                            ],
                          ),
                          if (_coverChoiceAvailable) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                _isAr
                                    ? 'صورة الغلاف في القائمة (عند وجود فيديو وصور)'
                                    : 'Listing cover (when both video and images exist)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SegmentedButton<bool>(
                              segments: [
                                ButtonSegment<bool>(
                                  value: false,
                                  label: Text(_isAr ? 'صورة' : 'Image'),
                                  icon: const Icon(Icons.image_outlined,
                                      size: 18),
                                ),
                                ButtonSegment<bool>(
                                  value: true,
                                  label: Text(_isAr ? 'فيديو' : 'Video'),
                                  icon: const Icon(Icons.play_circle_outline,
                                      size: 18),
                                ),
                              ],
                              selected: <bool>{_coverHeroIsVideo},
                              onSelectionChanged: (_saving || exhausted)
                                  ? null
                                  : (s) => setState(
                                        () => _coverHeroIsVideo = s.first,
                                      ),
                              emptySelectionAllowed: false,
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            _isAr
                                ? 'لا يُخزَّن رقم جوال المالك على الإعلان. للمهتمين: الدردشة داخل التطبيق، وجوال المسوّق يظهر من بيانات ترخيص الهيئة عند توفرها.'
                                : 'Owner phone is not stored on the listing. Buyers use in-app chat; marketer contact comes from REGA license data when available.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: cs.outlineVariant.withOpacity(0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _isAr ? 'صور الإعلان' : 'Listing images',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed:
                                  (_saving || _isGuest || _picking || exhausted)
                                      ? null
                                      : _pickImages,
                              icon: _picking
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: AppLogoLoading(
                                        compact: true,
                                        size: 20,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.add_photo_alternate_outlined),
                              label: Text(_isAr ? 'إضافة صور' : 'Add images'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_items.isEmpty)
                          Text(
                            _isAr ? 'لا توجد صور' : 'No images',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: List.generate(_items.length, (i) {
                              final it = _items[i];
                              final img = it.isExisting
                                  ? Image.network(
                                      _imgPublicUrl(it.path!),
                                      fit: BoxFit.cover,
                                    )
                                  : Image.memory(
                                      it.bytes!,
                                      fit: BoxFit.cover,
                                    );

                              return _ImageTile(
                                index: i,
                                image: img,
                                disabled: _saving ||
                                    _isGuest ||
                                    _picking ||
                                    exhausted,
                                onRemove: () => _removeAt(i),
                                onMoveLeft:
                                    i == 0 ? null : () => _move(i, i - 1),
                                onMoveRight: i == _items.length - 1
                                    ? null
                                    : () => _move(i, i + 1),
                              );
                            }),
                          ),
                        const SizedBox(height: 10),
                        Text(
                          _isAr
                              ? 'رتّب الصور: الأولى هي صورة الغلاف.'
                              : 'Reorder images: the first image is the cover.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: (_saving || _isGuest || _picking || exhausted)
                          ? null
                          : _save,
                      icon: _saving
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: AppLogoLoading(compact: true, size: 20),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        exhausted
                            ? (_isAr
                                ? 'تم استنفاد التعديلات'
                                : 'Edit limit reached')
                            : (_isAr ? 'حفظ التعديلات' : 'Save changes'),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _secTitle(String t) => Text(
        t,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      );

  Widget _numDrop({
    required String label,
    required int? value,
    required int min,
    required int max,
    required ValueChanged<int?> onChanged,
    required bool disabled,
  }) {
    final items = <DropdownMenuItem<int?>>[
      DropdownMenuItem<int?>(
        value: null,
        child: Text(_isAr ? 'اختياري' : 'Optional'),
      ),
    ];

    for (int i = min; i <= max; i++) {
      items.add(
        DropdownMenuItem<int?>(
          value: i,
          child: Text(i.toString()),
        ),
      );
    }

    return DropdownButtonFormField<int?>(
      value: value,
      items: items,
      onChanged: disabled ? null : onChanged,
      decoration: InputDecoration(
        labelText: label,
      ),
    );
  }

  String _amenityLabel(String k) {
    switch (k) {
      case 'pool':
        return _isAr ? 'مسبح' : 'Pool';
      case 'gym':
        return _isAr ? 'نادي' : 'Gym';
      case 'elevator':
        return _isAr ? 'مصعد' : 'Elevator';
      case 'security':
        return _isAr ? 'أمن' : 'Security';
      case 'garden':
        return _isAr ? 'حديقة' : 'Garden';
      case 'balcony':
        return _isAr ? 'شرفة' : 'Balcony';
      case 'ac':
        return _isAr ? 'مكيف' : 'AC';
      case 'parking':
        return _isAr ? 'مواقف' : 'Parking';
      case 'wifi':
        return _isAr ? 'واي فاي' : 'Wi-Fi';
      default:
        return k;
    }
  }
}

class _ImageTile extends StatelessWidget {
  final int index;
  final Widget image;
  final bool disabled;
  final VoidCallback onRemove;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;

  const _ImageTile({
    required this.index,
    required this.image,
    required this.disabled,
    required this.onRemove,
    required this.onMoveLeft,
    required this.onMoveRight,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Container(
          width: 120,
          height: 120,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outlineVariant.withOpacity(0.6),
            ),
          ),
          child: image,
        ),
        Positioned(
          top: 6,
          left: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(0.9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: cs.outlineVariant.withOpacity(0.6),
              ),
            ),
            child: Text(
              '#${index + 1}',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: IconButton(
            onPressed: disabled ? null : onRemove,
            icon: const Icon(Icons.close),
            style: IconButton.styleFrom(
              backgroundColor: cs.surface.withOpacity(0.9),
              foregroundColor: cs.error,
              padding: const EdgeInsets.all(6),
            ),
          ),
        ),
        Positioned(
          bottom: 6,
          right: 6,
          child: Row(
            children: [
              IconButton(
                onPressed: disabled ? null : onMoveLeft,
                icon: const Icon(Icons.chevron_left),
                style: IconButton.styleFrom(
                  backgroundColor: cs.surface.withOpacity(0.9),
                  foregroundColor: cs.onSurface,
                  padding: const EdgeInsets.all(6),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: disabled ? null : onMoveRight,
                icon: const Icon(Icons.chevron_right),
                style: IconButton.styleFrom(
                  backgroundColor: cs.surface.withOpacity(0.9),
                  foregroundColor: cs.onSurface,
                  padding: const EdgeInsets.all(6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditImageItem {
  final bool isExisting;
  final String? rowId;
  final String? path;
  final String? name;
  final Uint8List? bytes;

  const _EditImageItem._({
    required this.isExisting,
    this.rowId,
    this.path,
    this.name,
    this.bytes,
  });

  factory _EditImageItem.existing({
    required String rowId,
    required String path,
  }) {
    return _EditImageItem._(
      isExisting: true,
      rowId: rowId,
      path: path,
    );
  }

  factory _EditImageItem.newOne({
    required String name,
    required Uint8List bytes,
  }) {
    return _EditImageItem._(
      isExisting: false,
      name: name,
      bytes: bytes,
    );
  }

  bool get isNew => !isExisting;
}
