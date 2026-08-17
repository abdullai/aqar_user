// lib/screens/add_property_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/branding/app_branding.dart';
import '../core/permissions/runtime_permission_helper.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show suspendAutoLock;
import '../services/marketing_flow_service.dart';
import '../services/org_activity_service.dart';
import '../services/saudi_districts_service.dart';
import '../services/saudi_locations_service.dart';
import '../services/watermark_service.dart';
import '../utils/video_duration_check.dart';
import '../core/forms/wizard_form_draft.dart';
import '../core/forms/wizard_step_navigation.dart';
import '../core/forms/active_form_guard.dart';
import '../core/forms/publish_content_fingerprint_store.dart';
import '../core/session/app_session.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/form_exit_confirm_dialog.dart';
import '../widgets/terms_acceptance_checkbox.dart';
import 'platform_policies_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/field_group_frame.dart';
import '../widgets/deed_date_calendar_dialog.dart';
import '../widgets/listing_pricing_breakdown.dart';
import '../widgets/adaptive_post_publish_dialog.dart';
import '../widgets/publisher_identity_options_card.dart';
import '../core/profile/publisher_identity_prefs.dart';
import '../widgets/stable_select_chip.dart';
import '../widgets/property_type_hierarchy_picker.dart';
import '../widgets/year_built_picker_field.dart';
import '../widgets/smart_count_field.dart';
import '../widgets/searchable_select_field.dart';
import '../core/input/input_normalizers.dart';
import '../core/input/saudi_input_formatters.dart';
import '../core/listing/listing_area_unit.dart';
import '../core/listing/marketing_add_property_flow_config.dart';
import '../core/subscription/app_subscription_gate.dart';
import '../core/subscription/subscription_gate_helper.dart';
import '../services/subscription_service.dart';
import '../core/workflow/app_role_helper.dart';
import '../core/session/account_role_cache.dart';
import '../core/listing/property_type_catalog.dart';
import '../core/listing/property_listing_display.dart';
import '../core/utils/app_money.dart';
import '../core/utils/display_ids.dart';
import '../core/utils/listing_date_display.dart';
import '../core/navigation/post_auth_navigation.dart';
import '../services/fal_license_service.dart';
import 'listing_request_status_page.dart';
import 'map_picker_page.dart';
import 'rega_ad_license_import_page.dart';
import 'subscriptions/subscriptions_root_screen.dart';

/// مصدر رخصة الإعلان (الخطوة الأولى من المعالج).
enum _AdLicenseSource { unset, inApp, external, none }

class AddPropertyPage extends StatefulWidget {
  final String userId;
  final String lang;

  /// بيانات مستخرجة من بوابة الهيئة بعد التحقق من فال (للمسوّقين/المنشآت).
  final Map<String, dynamic>? initialRegaPayload;

  /// مسار مسوّق/منشأة من [MarketingListingEntryPage].
  final MarketingAddPropertyFlowConfig? marketingFlow;

  /// عند `true`: لا يُعرض سهم الرجوع الداخلي — يعتمد على شريط لوحة الداشبورد.
  final bool embedAppBar;

  const AddPropertyPage({
    super.key,
    required this.userId,
    required this.lang,
    this.initialRegaPayload,
    this.marketingFlow,
    this.embedAppBar = false,
  });

  @override
  State<AddPropertyPage> createState() => _AddPropertyPageState();
}

enum _PickSource { files, gallery, camera }

const String _kManualOptionValue = '__manual__';

/// شرائح النموذج داخل معالج الخطوات (كل شريحة لها [Form] مستقل للتحقق).
enum AddPropertyFormSlice {
  classification,
  location,
  pricing,
  details,
}

String _formSliceTitle(AddPropertyFormSlice s, bool isAr) {
  switch (s) {
    case AddPropertyFormSlice.classification:
      return isAr ? 'التصنيف' : 'Classification';
    case AddPropertyFormSlice.location:
      return isAr ? 'الموقع' : 'Location';
    case AddPropertyFormSlice.pricing:
      return isAr ? 'الصك والتسعير' : 'Deed & pricing';
    case AddPropertyFormSlice.details:
      return isAr ? 'تفاصيل العقار' : 'Property details';
  }
}

String _formSliceHint(AddPropertyFormSlice s, bool isAr) {
  switch (s) {
    case AddPropertyFormSlice.classification:
      return isAr ? 'النوع، الاستخدام، الغرض.' : 'Type, usage, purpose.';
    case AddPropertyFormSlice.location:
      return isAr
          ? 'منطقة، محافظة، مدينة، حي (يُكمَل تلقائياً بعد الخريطة إن وُجدت).'
          : 'Region, governorate, city, district (prefilled after map if used).';
    case AddPropertyFormSlice.pricing:
      return isAr
          ? 'حسب الغرض: صك/عنوان/وصف/مساحة/سعر.'
          : 'Per purpose: deed, title, description, area, price.';
    case AddPropertyFormSlice.details:
      return isAr
          ? 'غرف، مرافق، … حسب النوع.'
          : 'Rooms, amenities, … as needed.';
  }
}

Color _purposeAccentColor(String code) {
  switch (code) {
    case 'sale':
      return const Color(0xFF0F766E);
    case 'rent':
    case 'daily_rent':
    case 'monthly_rent':
    case 'yearly_rent':
      return const Color(0xFF2563EB);
    case 'auction':
      return const Color(0xFFEA580C);
    case 'investment':
      return const Color(0xFF7C3AED);
    default:
      return Colors.blueGrey;
  }
}

class _AddPropertyPageState extends State<AddPropertyPage> {
  static const int _kMaxVideoSeconds = 120;
  static const int _kMaxVideoBytes = 50 * 1024 * 1024;

  final _sb = Supabase.instance.client;
  final _formKeyClassification = GlobalKey<FormState>();
  final _formKeyLocation = GlobalKey<FormState>();
  final _formKeyPricing = GlobalKey<FormState>();
  final _formKeyDetails = GlobalKey<FormState>();
  final _formKeyCoords = GlobalKey<FormState>();
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _listingMediaKey = GlobalKey();
  final GlobalKey _coordsKey = GlobalKey();
  final GlobalKey _regaCardKey = GlobalKey();
  final GlobalKey _formCardKey = GlobalKey();

  bool _picking = false;

  // الحقول الأساسية
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _region = TextEditingController();
  final _governorate = TextEditingController();
  final _city = TextEditingController();
  final _location = TextEditingController();
  final _addressLine = TextEditingController();
  final _buildingNumber = TextEditingController();
  final _deedNumber = TextEditingController();
  final _deedIssuer = TextEditingController();
  final _area = TextEditingController();
  final _price = TextEditingController();

  // العملة والتفاوض والمزاد
  String _currency = 'SAR';
  bool _negotiable = false;
  /// على السوم (بدون سعر ثابت محدد).
  bool _priceOnSum = false;
  /// قبول التمويل العقاري.
  bool _acceptsMortgageFinance = false;
  /// إقرار: لا مانع من التصرف/الانتفاع.
  bool _noLegalObstacles = false;
  /// صفة المعلن: owner | broker | authorized
  String _advertiserRole = 'owner';
  /// موقع تقريبي (لا يُعرض بدقة على خريطة الإعلانات).
  bool _locationIsApproximate = false;
  /// إظهار اسم/صفة المعلن مع التوثيق على بطاقات الرئيسية (اختياري).
  bool _showOwnerNameOnCards = true;
  PublicNameSource _pubNameSource = PublicNameSource.official;
  PublicPhoneSource _pubPhoneSource = PublicPhoneSource.primary;
  bool _publishPresenceOnCards = true;
  String _officialNameCached = '';
  String _displayAliasCached = '';
  String _primaryPhoneCached = '';
  String _secondaryPhoneCached = '';
  /// عمر العقار كفئة واجهة: new | 1_5 | 6_10 | 11_20 | 20_plus
  String? _propertyAgeBucket;
  bool _isAuction = false;
  final _currentBid = TextEditingController();

  // --- فوترة الإعلان: ضريبة القيمة المضافة 5% + عمولة التسويق العقاري ---
  // — `null` يعني أن المعلن لم يجب بعد على السؤال الأول (واجب قبل النشر).
  bool? _priceIncludesVat;
  // — `none` افتراضياً؛ يتحوّل إلى `percent` (2.5%) أو `fixed` (مبلغ مقطوع).
  String _commissionKind = 'none';
  final TextEditingController _commissionFixedCtrl = TextEditingController();
  static const double _kVatRate = 0.05;
  static const double _kMarketingCommissionRate = 0.025;
  // — قفل النشر: يبقى مرفوعاً حتى انتهاء حوار النجاح ورمز الإعلان كي لا يُنشر مرتين.
  bool _publishLock = false;
  /// بعد نجاح النشر: اسمح بـ pop للرئيسية حتى لو بقيت الحقول ممتلئة.
  bool _publishSucceeded = false;
  bool _termsAccepted = false;
  static const _draftNamespace = 'add_property_listing';
  AppSession? _appSession;

  // نوع العرض (بيع/إيجار/مزاد/استثمار)
  String _purpose = 'sale';

  // حقول إضافية عامة
  int? _bedrooms;
  int? _bathrooms;
  int? _parkingSpots;
  bool _furnished = false;
  int? _yearBuilt;
  int? _floor;
  int? _totalFloors;

  final _videoUrl = TextEditingController();
  final _virtualTourUrl = TextEditingController();
  DateTime? _availabilityDate;
  DateTime? _deedDate;
  bool _uploadingVideo = false;

  // حقول خاصة بالشقة
  int? _livingRooms;
  int? _kitchens;
  bool _hasElevator = false;
  bool _independentEntrance = false;
  bool _hasCentralAc = false;
  bool _hasSplitAc = false;

  // حقول خاصة بالفيلا
  int? _majlisCount;
  int? _annexCount;
  bool _hasGarden = false;
  bool _hasPool = false;
  bool _hasCourtyard = false;
  bool _carEntrance = false;
  bool _internalStair = false;
  bool _separateApartment = false;
  bool _hasDriverRoom = false;
  bool _hasMaidRoom = false;
  bool _hasStorageRoom = false;

  // حقول خاصة بالبناء/المستودع/المشروع
  int? _floorsCount;
  int? _unitsCount;
  double? _plotArea;
  bool _hasLoadingDock = false;
  bool _hasCrane = false;
  String? _projectType;

  // حقول خاصة بالأرض
  String? _landUse;
  String? _facade;
  int? _streetCount;
  final _streetWidth1 = TextEditingController();
  final _streetWidth2 = TextEditingController();
  final _streetWidth3 = TextEditingController();
  final _streetWidth4 = TextEditingController();
  bool _isCornerLand = false;
  final _planNumber = TextEditingController();
  final _parcelNumber = TextEditingController();

  /// حدود القطعة (اختياري) — يُخزَّن ضمن `listing_guidance`.
  final _boundaryNorth = TextEditingController();
  final _boundarySouth = TextEditingController();
  final _boundaryEast = TextEditingController();
  final _boundaryWest = TextEditingController();

  // المرافق الموسعة
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
    'maid_room': false,
    'driver_room': false,
    'storage': false,
    'roof': false,
    'kitchen': false,
    'majlis': false,
    'yard': false,
  };

  // نوع العقار الموسع
  String _type = 'villa';

  bool _saving = false;
  String? _error;

  /// 0: رخصة/هيئة — 1: تصنيف — 2: خريطة — 3: موقع — 4: صك/تسعير — 5: تفاصيل — 6: وسائط
  int _wizardStep = 0;

  /// «بيع / إيجار / شراء» في مسار المسوّق المرخّص.
  String _primaryPurposeGroup = 'sale';

  /// تصنيف مبسّط (سكني، تجاري، …) عند عدم وجود ترخيص.
  String _propertyCategory = 'residential';

  /// غرض فرعي: إيجار (يومي/شهري/سنوي) أو بيع (مزاد/استثمار).
  String? _subPurposeCode;

  int get _kWizardLastStep =>
      _marketingLicensedSplit ? 7 : 6;

  bool get _marketingFlowActive => widget.marketingFlow != null;

  bool get _marketingLicensedSplit =>
      widget.marketingFlow?.licensedSplitSteps == true;

  bool get _marketingSimplifiedForm =>
      widget.marketingFlow?.simplifiedOwnerForm == true;

  /// يُدمَج في عمود `rega_payload` عند الحفظ.
  Map<String, dynamic> _regaPayloadForInsert = {};

  // المالك الفرد يستطيع إنشاء إعلان أولي دون رخصة فال؛ المسوق يدخل عبر بوابة الهيئة.
  _AdLicenseSource _adLicenseSource = _AdLicenseSource.none;

  /// إلزامي: هل على العقار التزامات (قيد/اشتراط)؟
  bool? _propertyHasObligations;

  final _obligationsDetail = TextEditingController();
  final _extendedUsageNotes = TextEditingController();

  /// مسار تخزين PDF رخصة الإعلان (عند اختيار رخصة خارج التطبيق).
  String? _licensePdfStoragePath;
  bool _uploadingLicensePdf = false;

  /// وحدة إدخال المساحة في النموذج (يُحوَّل للم² عند الحفظ).
  ListingAreaUnit _areaUnit = ListingAreaUnit.m2;

  /// اسم العرض لمسوّق موثّق (سطر «نشر بواسطة»).
  String? _marketerPublishName;

  /// رقم رخصة فال/الوساطة (10 أرقام) للتحقق عبر الهيئة.
  final _regaFalLicenseNo = TextEditingController();
  Timer? _regaDebounce;
  bool _regaChecking = false;
  String? _regaVerifyBanner;
  bool? _regaVerifyOk;

  // الصور
  final List<_PickedImage> _images = [];

  /// عند وجود فيديو + صور: ما يُعرض أولاً في المعرض (فيديو أو أول صورة بعد الترتيب).
  bool _coverHeroIsVideo = true;

  /// مناسب لسكني / تجاري (يمكن اختيار واحد أو كليهما).
  bool _usageResidential = false;
  bool _usageCommercial = false;

  // الإحداثيات
  bool _useMapCoords = true;
  double? _lat;
  double? _lng;
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  // اسم المالك
  String? _ownerFirstName;
  String? _ownerLastName;

  // بيانات المناطق/المدن
  bool _locationsLoading = false;
  final List<String> _regionOptions = [];
  final Map<String, List<String>> _governoratesByRegion = {};
  final Map<String, List<String>> _citiesByGovernorate = {};
  bool _regionManual = false;
  bool _governorateManual = false;
  bool _cityManual = false;
  String? _selectedRegion;
  String? _selectedGovernorate;
  String? _selectedCity;

  Map<String, List<String>> _districtsByCity = {};
  bool _districtManual = false;
  String? _selectedDistrict;

  bool get _isAr => widget.lang == 'ar';

  String get _resolvedAccountType {
    final fromFlow = (widget.marketingFlow?.accountType ?? '').trim();
    if (fromFlow.isNotEmpty) return fromFlow;
    final cached = (AccountRoleCache.snapshot?.accountType ?? '').trim();
    if (cached.isNotEmpty) return cached;
    return 'user';
  }

  String get _advertiserRoleLabel => SubscriptionService.planAudienceLabel(
        isAr: _isAr,
        accountType: _resolvedAccountType,
      );

  /// قيم الحفظ: owner للمالك/العام، broker لأي دور تسويقي/منشأة.
  String get _advertiserRoleCode {
    final k = AppRoleHelper.fromAccountType(_resolvedAccountType);
    return AppRoleHelper.isMarketingRole(k) ? 'broker' : 'owner';
  }

  List<String> get _currentDistrictOptions {
    final city = (_selectedCity ?? _city.text).trim();
    if (city.isEmpty) return const [];
    final list = _districtsByCity[city];
    if (list != null && list.isNotEmpty) return list;
    return const [];
  }

  List<String> get _currentGovernorateOptions {
    final key = (_selectedRegion ?? '').trim();
    if (key.isEmpty) return const [];
    return _governoratesByRegion[key] ?? const [];
  }

  List<String> get _currentCityOptions {
    final key = (_selectedGovernorate ?? '').trim();
    if (key.isEmpty) return const [];
    return _citiesByGovernorate[key] ?? const [];
  }

  bool get _isLand => PropertyTypeCatalog.isLandLikeEffective(_type);

  bool get _isApartmentLike => PropertyTypeCatalog.isApartmentLike(_type);

  bool get _isVillaLike => PropertyTypeCatalog.isVillaLike(_type);

  bool get _isBuilding =>
      _type == 'building' ||
      _type == 'commercial_building' ||
      _type == 'apartment_building';
  bool get _isWarehouse => _type == 'warehouse';
  bool get _isProject => _type == 'project';
  bool get _isOther => _type == 'other';

  /// بيع / مزاد / استثمار يتطلب بيانات الصك
  bool get _requiresDeed =>
      const {'sale', 'auction', 'investment'}.contains(_purpose);

  bool get _showBuildingNumber =>
      PropertyTypeCatalog.showsBuildingNumber(_type);

  /// توافق الحفظ مع النوع المخصص والمجموعة.
  bool get _roomStatsForSave =>
      PropertyTypeCatalog.showsResidentialRoomBedCountsEffective(_type) &&
      !_isProject;

  bool get _showResidentialBedBath =>
      PropertyTypeCatalog.showsResidentialRoomBedCountsEffective(_type) &&
      !_isProject;

  bool get _showParkingYearRow =>
      PropertyTypeCatalog.showsParkingYearRowEffective(_type);

  bool get _showFurnishedRow =>
      PropertyTypeCatalog.showsFurnishedRowEffective(_type);

  bool get _showFloorFieldsRow =>
      PropertyTypeCatalog.showsFloorFieldsEffective(_type);

  bool get _showFloorFields =>
      PropertyTypeCatalog.showsFloorFieldsEffective(_type);

  static String normalizeDeedNumber(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), '').trim();

  final List<Map<String, String>> _purposeTypes = [
    {'code': 'sale', 'ar': 'بيع', 'en': 'Sale'},
    {'code': 'rent', 'ar': 'إيجار', 'en': 'Rent'},
    {'code': 'daily_rent', 'ar': 'إيجار يومي', 'en': 'Daily Rent'},
    {'code': 'monthly_rent', 'ar': 'إيجار شهري', 'en': 'Monthly Rent'},
    {'code': 'yearly_rent', 'ar': 'إيجار سنوي', 'en': 'Yearly Rent'},
    {'code': 'auction', 'ar': 'مزاد', 'en': 'Auction'},
    {'code': 'investment', 'ar': 'استثمار', 'en': 'Investment'},
  ];

  @override
  void initState() {
    super.initState();
    final uid = _sb.auth.currentUser?.id ?? '';
    if (uid.isEmpty ||
        (widget.userId.trim().isNotEmpty && widget.userId.trim() != uid)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              _isAr
                  ? 'غير مصرح لك بفتح هذه الصفحة'
                  : 'Not allowed to open this page',
            ),
          ),
        );
        Navigator.pop(context);
      });
      return;
    }
    _loadSaudiLocations();
    _loadOwnerName();
    _restoreTempCoords();
    _advertiserRole = _advertiserRoleCode;
    _wireAddPropertyNumericListeners();
    _price.addListener(_onPriceOrAreaChanged);
    _area.addListener(_onPriceOrAreaChanged);
    _regaFalLicenseNo.addListener(_scheduleRegaLicenseVerify);
    _applyInitialRegaPayload();
    _applyMarketingFlowBootstrap();
    if (_marketingFlowActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_ensureMarketingSubscriptionForAddProperty());
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncAdvertiserRoleFromAccount();
      _appSession = context.read<AppSession>();
      _appSession?.addListener(_onConnectivityForDraft);
      ActiveFormGuard.instance.register(
        ActiveFormGuardHandle(
          id: 'add_property_listing',
          hasUnsavedInput: _hasUnsavedWizardInput,
          isPublishing: () => _saving || _publishLock,
          onSaveDraft: () => _persistListingDraft(showSnack: false),
          onDiscard: _clearListingDraftAndForm,
          leaveTitleAr: 'هل تريد إغلاق الإعلان؟',
          leaveTitleEn: 'Leave this listing?',
        ),
      );
      unawaited(_restoreListingDraftIfAny());
    });
  }

  void _syncAdvertiserRoleFromAccount() {
    final next = _advertiserRoleCode;
    if (_advertiserRole == next) return;
    if (mounted) {
      setState(() => _advertiserRole = next);
    } else {
      _advertiserRole = next;
    }
  }

  void _onConnectivityForDraft() {
    if (!_hasUnsavedWizardInput()) return;
    if (_appSession?.hasInternet == false) {
      unawaited(_persistListingDraft(showSnack: false));
    }
  }

  bool _hasUnsavedWizardInput() {
    if (_publishSucceeded) return false;
    return _title.text.trim().isNotEmpty ||
        _desc.text.trim().isNotEmpty ||
        _region.text.trim().isNotEmpty ||
        _city.text.trim().isNotEmpty ||
        _price.text.trim().isNotEmpty ||
        _area.text.trim().isNotEmpty ||
        _images.isNotEmpty;
  }

  /// إغلاق نموذج الإضافة والعودة للوحة على تبويب الرئيسية (بدون إعادة بناء الويب).
  Future<void> _popToDashboardHomeAfterPublish() async {
    _publishSucceeded = true;
    if (mounted) setState(() => _publishLock = false);
    ActiveFormGuard.instance.unregister('add_property_listing');
    final uid = _sb.auth.currentUser?.id ?? '';
    if (uid.isNotEmpty) {
      unawaited(
        WizardFormDraft.clear(namespace: _draftNamespace, userId: uid),
      );
    }
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(true);
      return;
    }
    await PostAuthNavigation.openDashboard(context);
  }

  Map<String, dynamic> _snapshotListingDraft() {
    return {
      'wizard_step': _wizardStep,
      'title': _title.text,
      'desc': _desc.text,
      'region': _region.text,
      'governorate': _governorate.text,
      'city': _city.text,
      'location': _location.text,
      'address_line': _addressLine.text,
      'building_number': _buildingNumber.text,
      'deed_number': _deedNumber.text,
      'deed_issuer': _deedIssuer.text,
      'price': _price.text,
      'area': _area.text,
      'current_bid': _currentBid.text,
      'commission_fixed': _commissionFixedCtrl.text,
      'video_url': _videoUrl.text,
      'virtual_tour_url': _virtualTourUrl.text,
      'lat': _latCtrl.text,
      'lng': _lngCtrl.text,
      'plan_number': _planNumber.text,
      'parcel_number': _parcelNumber.text,
      'obligations_detail': _obligationsDetail.text,
      'extended_usage_notes': _extendedUsageNotes.text,
      'rega_fal_license_no': _regaFalLicenseNo.text,
      'purpose': _purpose,
      'type': _type,
      'currency': _currency,
      'commission_kind': _commissionKind,
      'selected_region': _selectedRegion,
      'selected_governorate': _selectedGovernorate,
      'usage_residential': _usageResidential,
      'usage_commercial': _usageCommercial,
      'negotiable': _negotiable,
      'price_on_sum': _priceOnSum,
      'accepts_mortgage_finance': _acceptsMortgageFinance,
      'no_legal_obstacles': _noLegalObstacles,
      'advertiser_role': _advertiserRole,
      'location_is_approximate': _locationIsApproximate,
      'property_age_bucket': _propertyAgeBucket,
      'is_auction': _isAuction,
      'furnished': _furnished,
      'use_map_coords': _useMapCoords,
      'price_includes_vat': _priceIncludesVat,
      'property_has_obligations': _propertyHasObligations,
      'ad_license_source': _adLicenseSource.name,
      'bedrooms': _bedrooms,
      'bathrooms': _bathrooms,
      'parking_spots': _parkingSpots,
      'year_built': _yearBuilt,
      'image_meta': _images
          .map((e) => {
                'name': e.name,
                'size': e.bytes.length,
              })
          .toList(),
      'image_b64': _images.length <= 4 &&
              _images.fold<int>(0, (s, e) => s + e.bytes.length) < 1200000
          ? _images
              .map((e) => {
                    'name': e.name,
                    'data': base64Encode(e.bytes),
                  })
              .toList()
          : null,
    };
  }

  void _applyListingDraft(Map<String, dynamic> d) {
    _wizardStep = (d['wizard_step'] as num?)?.toInt() ?? 0;
    _title.text = '${d['title'] ?? ''}';
    _desc.text = '${d['desc'] ?? ''}';
    _region.text = '${d['region'] ?? ''}';
    _governorate.text = '${d['governorate'] ?? ''}';
    _city.text = '${d['city'] ?? ''}';
    _location.text = '${d['location'] ?? ''}';
    _addressLine.text = '${d['address_line'] ?? ''}';
    _buildingNumber.text = '${d['building_number'] ?? ''}';
    _deedNumber.text = '${d['deed_number'] ?? ''}';
    _deedIssuer.text = '${d['deed_issuer'] ?? ''}';
    _price.text = '${d['price'] ?? ''}';
    _area.text = '${d['area'] ?? ''}';
    _currentBid.text = '${d['current_bid'] ?? ''}';
    _commissionFixedCtrl.text = '${d['commission_fixed'] ?? ''}';
    _videoUrl.text = '${d['video_url'] ?? ''}';
    _virtualTourUrl.text = '${d['virtual_tour_url'] ?? ''}';
    _latCtrl.text = '${d['lat'] ?? ''}';
    _lngCtrl.text = '${d['lng'] ?? ''}';
    _planNumber.text = '${d['plan_number'] ?? ''}';
    _parcelNumber.text = '${d['parcel_number'] ?? ''}';
    _obligationsDetail.text = '${d['obligations_detail'] ?? ''}';
    _extendedUsageNotes.text = '${d['extended_usage_notes'] ?? ''}';
    _regaFalLicenseNo.text = '${d['rega_fal_license_no'] ?? ''}';
    _purpose = '${d['purpose'] ?? _purpose}';
    _type = '${d['type'] ?? _type}';
    _currency = '${d['currency'] ?? _currency}';
    _commissionKind = '${d['commission_kind'] ?? _commissionKind}';
    _selectedRegion = d['selected_region']?.toString();
    _selectedGovernorate = d['selected_governorate']?.toString();
    _usageResidential = d['usage_residential'] == true;
    _usageCommercial = d['usage_commercial'] == true;
    _negotiable = d['negotiable'] == true;
    _priceOnSum = d['price_on_sum'] == true;
    _acceptsMortgageFinance = d['accepts_mortgage_finance'] == true;
    _noLegalObstacles = d['no_legal_obstacles'] == true;
    _advertiserRole = (d['advertiser_role'] ?? 'owner').toString().trim();
    if (_advertiserRole.isEmpty) _advertiserRole = 'owner';
    // بعد المسودة: اضبط صفة المعلن من نوع الحساب الفعلي (لا تعتمد على مسودة قديمة).
    _advertiserRole = _advertiserRoleCode;
    _locationIsApproximate = d['location_is_approximate'] == true;
    _propertyAgeBucket = d['property_age_bucket']?.toString();
    _isAuction = d['is_auction'] == true;
    _furnished = d['furnished'] == true;
    _useMapCoords = d['use_map_coords'] == true;
    _priceIncludesVat = d['price_includes_vat'] as bool?;
    _propertyHasObligations = d['property_has_obligations'] as bool?;
    final als = '${d['ad_license_source'] ?? ''}';
    if (als.isNotEmpty) {
      try {
        _adLicenseSource = _AdLicenseSource.values.byName(als);
      } catch (_) {}
    }
    _bedrooms = (d['bedrooms'] as num?)?.toInt();
    _bathrooms = (d['bathrooms'] as num?)?.toInt();
    _parkingSpots = (d['parking_spots'] as num?)?.toInt();
    _yearBuilt = (d['year_built'] as num?)?.toInt();
    _images.clear();
    final imgs = d['image_b64'];
    if (imgs is List) {
      for (final raw in imgs) {
        if (raw is! Map) continue;
        final name = '${raw['name'] ?? 'photo.jpg'}';
        final b64 = '${raw['data'] ?? ''}';
        if (b64.isEmpty) continue;
        try {
          _images.add(_PickedImage(name: name, bytes: base64Decode(b64)));
        } catch (_) {}
      }
    }
  }

  Future<void> _restoreListingDraftIfAny() async {
    final uid = _sb.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return;
    final draft = await WizardFormDraft.load(
      namespace: _draftNamespace,
      userId: uid,
    );
    if (!mounted || draft == null || _hasUnsavedWizardInput()) return;
    setState(() => _applyListingDraft(draft));
    _scrollWizardStepToTop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(_isAr
            ? 'تم استرجاع مسودة الإعلان — أكمل من حيث توقفت.'
            : 'Listing draft restored — continue where you left off.'),
      ),
    );
  }

  Future<void> _persistListingDraft({bool showSnack = true}) async {
    final uid = _sb.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return;
    await WizardFormDraft.save(
      namespace: _draftNamespace,
      userId: uid,
      data: _snapshotListingDraft(),
    );
    if (showSnack && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(_isAr
              ? 'تم حفظ مسودة الإعلان.'
              : 'Listing draft saved.'),
        ),
      );
    }
  }

  Future<void> _clearListingDraftAndForm() async {
    final uid = _sb.auth.currentUser?.id ?? '';
    if (uid.isNotEmpty) {
      await WizardFormDraft.clear(namespace: _draftNamespace, userId: uid);
    }
    _title.clear();
    _desc.clear();
    _region.clear();
    _governorate.clear();
    _city.clear();
    _location.clear();
    _addressLine.clear();
    _price.clear();
    _area.clear();
    _wizardStep = _marketingFlowActive ? 1 : 0;
    _termsAccepted = false;
    _images.clear();
    if (mounted) setState(() {});
  }

  Future<void> _handleListingFormExit() async {
    final choice = await showFormExitConfirmDialog(
      context: context,
      isAr: _isAr,
      title: _isAr ? 'هل تريد إغلاق الإعلان؟' : 'Leave this listing?',
    );
    if (!mounted || choice == null || choice == FormExitChoice.keepEditing) {
      return;
    }
    if (choice == FormExitChoice.saveDraft) {
      await _persistListingDraft();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await _clearListingDraftAndForm();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _ensureMarketingSubscriptionForAddProperty() async {
    if (!mounted) return;
    final ok = await SubscriptionGateHelper.ensure(
      context,
      isAr: _isAr,
      action: SubscriptionGateAction.addPropertyListing,
      onGoSubscribe: () async {
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => SubscriptionsRootScreen(
              lang: widget.lang,
              accountType: widget.marketingFlow?.accountType ?? '',
              embedAppBar: !widget.embedAppBar,
            ),
          ),
        );
        if (mounted) {
          await SubscriptionGateHelper.refresh(context, force: true);
        }
      },
    );
    if (!ok && mounted) {
      Navigator.pop(context);
    }
  }

  void _applyMarketingFlowBootstrap() {
    final flow = widget.marketingFlow;
    if (flow == null) return;

    if (flow.skipLicenseStep) {
      _wizardStep = 1;
      if (flow.path == MarketingListingPath.licensed) {
        _adLicenseSource = _AdLicenseSource.inApp;
        _propertyHasObligations = false;
      } else {
        _adLicenseSource = _AdLicenseSource.none;
        _regaPayloadForInsert = {
          ..._regaPayloadForInsert,
          'no_license_market_consent': true,
          'market_without_rega_license': true,
        };
        _usageResidential = true;
        _subPurposeCode = 'sale';
        _primaryPurposeGroup = 'sale';
      }
    }

    final payload = flow.initialRegaPayload ?? widget.initialRegaPayload;
    if (payload != null && payload.isNotEmpty) {
      _regaPayloadForInsert = {
        ..._regaPayloadForInsert,
        ...payload,
      };
    }
  }

  /// يعيد ترتيب خطوات المعالج للمسار المرخّص (غرض → نوع → موقع → خريطة …).
  int _wizardPaneKind(int step) {
    if (!_marketingLicensedSplit) return step;
    switch (step) {
      case 1:
        return 101;
      case 2:
        return 102;
      case 3:
        return 3;
      case 4:
        return 2;
      case 5:
        return 4;
      case 6:
        return 5;
      case 7:
        return 6;
      default:
        return step;
    }
  }

  void _syncPurposeFromPrimaryGroup() {
    switch (_primaryPurposeGroup) {
      case 'rent':
        _purpose = _subPurposeCode ?? 'monthly_rent';
        break;
      case 'purchase':
        _purpose = 'sale';
        break;
      case 'sale':
      default:
        _purpose = _subPurposeCode ?? 'sale';
        break;
    }
  }

  void _applyPropertyCategoryDefaults() {
    switch (_propertyCategory) {
      case 'commercial':
        _usageCommercial = true;
        _usageResidential = false;
        if (_type == 'villa') _type = 'commercial_building';
        break;
      case 'administrative':
        _usageCommercial = true;
        _usageResidential = false;
        if (_type == 'villa') _type = 'office';
        break;
      case 'land':
        _usageResidential = false;
        _usageCommercial = false;
        _type = 'land';
        break;
      case 'farm':
        _usageResidential = false;
        _usageCommercial = false;
        _type = 'farm';
        break;
      case 'project':
        _usageResidential = false;
        _usageCommercial = true;
        _type = 'project';
        break;
      case 'other':
        _usageResidential = true;
        _usageCommercial = true;
        _type = 'other';
        break;
      case 'residential':
      default:
        _usageResidential = true;
        _usageCommercial = false;
        if (_type == 'land' || _type == 'farm' || _type == 'project') {
          _type = 'villa';
        }
        break;
    }
  }

  void _refreshAutoTitle() {
    if (_marketingFlowActive) {
      final city = (_selectedCity ?? _city.text).trim();
      final typeLabel = PropertyTypeCatalog.label(_type, _isAr);
      final purposeLabel = _purposeTypes
          .firstWhere(
            (e) => e['code'] == _purpose,
            orElse: () => {'ar': '', 'en': ''},
          );
      final pLabel = _isAr
          ? (purposeLabel['ar'] ?? '')
          : (purposeLabel['en'] ?? '');
      final parts = <String>[
        if (typeLabel.isNotEmpty) typeLabel,
        if (city.isNotEmpty) city,
        if (pLabel.isNotEmpty) pLabel,
      ];
      if (parts.isEmpty) return;
      _title.text = parts.join(' · ');
      return;
    }
    _maybeSuggestSmartTitle();
  }

  void _applyInitialRegaPayload() {
    final m = widget.initialRegaPayload;
    if (m == null || m.isEmpty) return;
    _adLicenseSource = _AdLicenseSource.inApp;
    _regaPayloadForInsert = Map<String, dynamic>.from(m);

    final pu = (m['rega_unit_price'] ?? '').toString();
    if (pu.isNotEmpty) {
      final cleaned = pu.replaceAll(',', '').replaceAll('٬', '').trim();
      final match = RegExp(r'[\d.]+').firstMatch(cleaned);
      if (match != null) _price.text = match.group(0) ?? '';
    }

    final deed = (m['deed_or_benefit_doc_number'] ?? '').toString().trim();
    if (deed.isNotEmpty) _deedNumber.text = deed;

    final pr = (m['rega_ad_purpose'] ?? '').toString();
    if (pr.isNotEmpty) {
      _purpose = _purposeFromRegaArabic(pr);
    }

    final titleHint =
        (m['marketer_entity_display_name'] ?? '').toString().trim();
    if (titleHint.isNotEmpty && _title.text.trim().isEmpty) {
      _title.text = titleHint;
    }

    final areaSqm = (m['rega_area_sqm'] ?? '').toString().trim();
    if (areaSqm.isNotEmpty) {
      final am = RegExp(r'[\d.]+')
          .firstMatch(areaSqm.replaceAll(',', '').replaceAll('٬', ''));
      if (am != null) _area.text = am.group(0) ?? '';
    }

    final rooms = (m['rega_rooms'] ?? '').toString().trim();
    if (rooms.isNotEmpty) {
      final rm = int.tryParse(
        RegExp(r'\d+').firstMatch(rooms)?.group(0) ?? '',
      );
      if (rm != null) _bedrooms = rm;
    }

    final city = (m['rega_city'] ?? '').toString().trim();
    if (city.isNotEmpty) _city.text = city;

    final reg = (m['rega_region'] ?? '').toString().trim();
    if (reg.isNotEmpty) _region.text = reg;

    final district = (m['rega_district'] ?? '').toString().trim();
    if (district.isNotEmpty) {
      _location.text = district;
    }

    final street = (m['rega_street'] ?? '').toString().trim();
    if (street.isNotEmpty) {
      _addressLine.text = street;
    }
  }

  String _purposeFromRegaArabic(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.contains('بيع') || t.contains('sale')) return 'sale';
    if (t.contains('مزاد')) return 'auction';
    if (t.contains('استثمار')) return 'investment';
    if (t.contains('يومي') || t.contains('daily')) return 'daily_rent';
    if (t.contains('شهري') || t.contains('monthly')) return 'monthly_rent';
    if (t.contains('سنوي') || t.contains('yearly')) return 'yearly_rent';
    if (t.contains('إيجار') || t.contains('rent')) return 'rent';
    return _purpose;
  }

  void _onPriceOrAreaChanged() {
    if (mounted) setState(() {});
  }

  double? _areaValueInSquareMeters() {
    final raw = double.tryParse(
      normalizeNumbers(_area.text).trim().replaceAll(',', ''),
    );
    return _areaUnit.toSquareMeters(raw);
  }

  double? _computedPricePerSqm() {
    final p = double.tryParse(
      normalizeNumbers(_price.text).trim().replaceAll(',', ''),
    );
    final a = _areaValueInSquareMeters();
    if (p == null || p <= 0 || a == null || a <= 0) return null;
    return AppMoney.roundPricePerSqm(p / a);
  }

  /// المبلغ المدخل في حقل «السعر الإجمالي» (موجب أو 0).
  double _enteredPriceValue() {
    return double.tryParse(
          normalizeNumbers(_price.text).trim().replaceAll(',', ''),
        ) ??
        0;
  }

  /// المبلغ المدخل في حقل «العمولة المقطوعة» (موجب أو 0).
  double _fixedCommissionValue() {
    return double.tryParse(
          normalizeNumbers(_commissionFixedCtrl.text)
              .trim()
              .replaceAll(',', ''),
        ) ??
        0;
  }

  /// نموذج فاتورة حيّ للمعاينة أسفل حقول السعر (يُحدَّث مع كل تغيير).
  ListingInvoiceModel _buildLiveInvoice() {
    return ListingInvoiceModel(
      enteredPrice: _enteredPriceValue(),
      priceIncludesVat: _priceIncludesVat ?? true,
      vatRate: _kVatRate,
      commissionKind: _commissionKind,
      commissionRate: _kMarketingCommissionRate,
      commissionAmount: _fixedCommissionValue(),
      currencyCode: _currency,
    );
  }

  void _scheduleRegaLicenseVerify() {
    _regaDebounce?.cancel();
    _regaDebounce = Timer(const Duration(milliseconds: 700), () async {
      final digits = _regaFalLicenseNo.text.replaceAll(RegExp(r'\D'), '');
      if (digits.length != 10) {
        if (mounted) {
          setState(() {
            _regaVerifyBanner = null;
            _regaVerifyOk = null;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _regaChecking = true;
          _regaVerifyBanner = _isAr
              ? 'جاري التحقق من الهيئة العامة للعقار أو الجهات المعنية عن رقم الترخيص…'
              : 'Verifying license with REGA and related authorities…';
        });
      }
      final res = await FalLicenseService(_sb).verify(digits);
      if (!mounted) return;
      setState(() {
        _regaChecking = false;
        _regaVerifyOk = res.valid;
        _regaVerifyBanner = res.valid
            ? (res.licenseStatusText ??
                (_isAr ? 'تم التحقق: رخصة سارية' : 'Verified: active license'))
            : (res.errorMessage ?? res.status);
      });
      if (res.valid) {
        _regaPayloadForInsert = {
          ..._regaPayloadForInsert,
          'fal_license_verify': {
            'status': res.status,
            'license_no': res.licenseNo,
            'broker_name': res.brokerName,
            'end_date': res.endDateIso,
          },
        };
      }
    });
  }

  Future<void> _openRegaImportPage() async {
    final m = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RegaAdLicenseImportPage(isAr: _isAr),
      ),
    );
    if (!mounted || m == null) return;
    setState(() {
      _regaPayloadForInsert = {..._regaPayloadForInsert, ...m};
      final n = (m['rega_ad_license_number'] ?? '').toString().trim();
      if (n.isNotEmpty) {
        _regaFalLicenseNo.text = n;
      }
    });
  }

  void _wireAddPropertyNumericListeners() {
    void warnNonNumericChars(String normalized) {
      if (RegExp(r'[a-zA-Z\u0600-\u06FF]').hasMatch(normalized)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              _isAr ? 'أدخل أرقامًا فقط' : 'Digits only',
            ),
          ),
        );
      }
    }

    void wireDigits(TextEditingController c) {
      c.addListener(() {
        final raw = normalizeAsciiDigits(c.text);
        warnNonNumericChars(raw);
        final n = digitsOnly(raw);
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
        warnNonNumericChars(t);
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
    wireDecimal(_commissionFixedCtrl);
    _commissionFixedCtrl.addListener(_onPriceOrAreaChanged);
    wireDigits(_buildingNumber);
    wireDigits(_deedNumber);
    wireDecimal(_streetWidth1);
    wireDecimal(_streetWidth2);
    wireDecimal(_streetWidth3);
    wireDecimal(_streetWidth4);
    wireDigits(_planNumber);
    wireDigits(_parcelNumber);
    wireDecimal(_latCtrl);
    wireDecimal(_lngCtrl);
  }

  @override
  void dispose() {
    ActiveFormGuard.instance.unregister('add_property_listing');
    _appSession?.removeListener(_onConnectivityForDraft);
    _title.dispose();
    _desc.dispose();
    _region.dispose();
    _governorate.dispose();
    _city.dispose();
    _location.dispose();
    _addressLine.dispose();
    _buildingNumber.dispose();
    _deedNumber.dispose();
    _deedIssuer.dispose();
    _obligationsDetail.dispose();
    _extendedUsageNotes.dispose();
    _regaDebounce?.cancel();
    _regaFalLicenseNo.removeListener(_scheduleRegaLicenseVerify);
    _regaFalLicenseNo.dispose();
    _price.removeListener(_onPriceOrAreaChanged);
    _area.removeListener(_onPriceOrAreaChanged);
    _area.dispose();
    _price.dispose();
    _commissionFixedCtrl.dispose();
    _currentBid.dispose();
    _videoUrl.dispose();
    _virtualTourUrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _streetWidth1.dispose();
    _streetWidth2.dispose();
    _streetWidth3.dispose();
    _streetWidth4.dispose();
    _planNumber.dispose();
    _parcelNumber.dispose();
    _boundaryNorth.dispose();
    _boundarySouth.dispose();
    _boundaryEast.dispose();
    _boundaryWest.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToKey(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
        alignment: 0.06,
      );
    });
  }

  bool get _requiresExternalLicenseBundle =>
      _adLicenseSource == _AdLicenseSource.external;

  bool get _canSubmit {
    if (!_termsAccepted) return false;
    if (!_noLegalObstacles) return false;
    if (_saving) return false;
    if (_publishLock) return false;
    if (_uploadingVideo) return false;
    if (_uploadingLicensePdf) return false;
    if (_adLicenseSource == _AdLicenseSource.unset) return false;
    if (_propertyHasObligations == null) return false;
    // — يجب الإجابة على سؤال «هل الإجمالي شامل ضريبة 5%؟».
    if (_priceIncludesVat == null) return false;
    // — اختيار «مبلغ مقطوع» يستوجب إدخال قيمة موجبة.
    if (_commissionKind == 'fixed' && _fixedCommissionValue() <= 0) {
      return false;
    }
    if (_propertyHasObligations == true &&
        _obligationsDetail.text.trim().length < 3) {
      return false;
    }
    final hasMedia = _images.isNotEmpty ||
        _videoUrl.text.trim().isNotEmpty ||
        (!_requiresExternalLicenseBundle);
    if (_requiresExternalLicenseBundle) {
      if (_images.isEmpty) return false;
      if (_videoUrl.text.trim().isEmpty) return false;
      if ((_licensePdfStoragePath ?? '').trim().isEmpty) return false;
    }
    if (_useMapCoords) {
      final lat = _parseNullableDouble(_latCtrl.text);
      final lng = _parseNullableDouble(_lngCtrl.text);
      if (lat == null || lng == null) return false;
    }
    if (!_marketingSimplifiedForm &&
        !_marketingLicensedSplit &&
        !_usageResidential &&
        !_usageCommercial) {
      return false;
    }
    if (_isLand && _streetCount != null && _streetCount! > 0) {
      final widths = _buildStreetWidths();
      if (widths.length < _streetCount!) return false;
    }
    if (_isAuction) {
      final bid = _parseDouble(_currentBid.text);
      if (bid <= 0) return false;
    }
    if (_requiresDeed) {
      if (normalizeDeedNumber(_deedNumber.text).isEmpty) return false;
      if (_deedDate == null) return false;
      if (_deedIssuer.text.trim().isEmpty) return false;
    }
    if (_showParkingYearRow && _yearBuilt == null) return false;
    return true;
  }

  String _wizardScreenTitle(bool isAr) {
    final pane = _wizardPaneKind(_wizardStep);
    switch (pane) {
      case 101:
        return isAr ? 'نوع الإعلان' : 'Listing type';
      case 102:
        return isAr ? 'نوع العقار' : 'Property type';
      case 0:
        return isAr ? 'الهيئة ورخصة الإعلان' : 'REGA & ad license';
      case 1:
        return isAr ? 'التصنيف' : 'Classification';
      case 2:
        return isAr ? 'الخريطة' : 'Map';
      case 3:
        return isAr ? 'الموقع' : 'Location';
      case 4:
        return isAr ? 'الصك والتسعير' : 'Deed & pricing';
      case 5:
        return isAr ? 'تفاصيل العقار' : 'Property details';
      case 6:
        return isAr ? 'الوسائط والنشر' : 'Media & publish';
      default:
        return isAr ? 'إضافة إعلان' : 'Add listing';
    }
  }

  bool _validateWizardStep(int step) {
    final pane = _wizardPaneKind(step);
    switch (pane) {
      case 0:
        if (_marketingFlowActive) return true;
        if (_adLicenseSource == _AdLicenseSource.unset) {
          final msg =
              _isAr ? 'اختر مصدر رخصة الإعلان' : 'Choose ad license source';
          setState(() => _error = msg);
          _scrollToKey(_regaCardKey);
          return false;
        }
        if (_propertyHasObligations == null) {
          final msg = _isAr
              ? 'حدد وجود التزامات على العقار'
              : 'Indicate if the property has obligations';
          setState(() => _error = msg);
          _scrollToKey(_regaCardKey);
          return false;
        }
        if (_propertyHasObligations == true &&
            _obligationsDetail.text.trim().length < 3) {
          final msg = _isAr
              ? 'وضّح التزامات العقار (3 أحرف على الأقل)'
              : 'Describe obligations (min. 3 characters)';
          setState(() => _error = msg);
          _scrollToKey(_regaCardKey);
          return false;
        }
        return true;
      case 101:
        _syncPurposeFromPrimaryGroup();
        return true;
      case 102:
        if (!(_formKeyClassification.currentState?.validate() ?? true)) {
          return false;
        }
        return true;
      case 1:
        if (_marketingSimplifiedForm) {
          _applyPropertyCategoryDefaults();
        } else if (!_marketingLicensedSplit &&
            !_usageResidential &&
            !_usageCommercial) {
          final msg = _isAr
              ? 'حدد الاستخدام (سكني / تجاري)'
              : 'Select usage (residential / commercial)';
          setState(() => _error = msg);
          return false;
        }
        if (_marketingSimplifiedForm && _propertyHasObligations == null) {
          final msg = _isAr
              ? 'حدد وجود التزامات على العقار'
              : 'Indicate if the property has obligations';
          setState(() => _error = msg);
          return false;
        }
        if (_marketingSimplifiedForm &&
            _propertyHasObligations == true &&
            _obligationsDetail.text.trim().length < 3) {
          final msg = _isAr
              ? 'وضّح التزامات العقار (3 أحرف على الأقل)'
              : 'Describe obligations (min. 3 characters)';
          setState(() => _error = msg);
          return false;
        }
        if (_marketingSimplifiedForm && _subPurposeCode == null) {
          final msg = _isAr ? 'اختر الغرض الفرعي' : 'Select sub-purpose';
          setState(() => _error = msg);
          return false;
        }
        if (!(_formKeyClassification.currentState?.validate() ?? false)) {
          return false;
        }
        _refreshAutoTitle();
        return true;
      case 2:
        if (!_useMapCoords) return true;
        final lat = _parseNullableDouble(_latCtrl.text);
        final lng = _parseNullableDouble(_lngCtrl.text);
        if (lat == null || lng == null) {
          final msg = _isAr
              ? 'حدد النقطة على الخريطة أو عطّل الخيار'
              : 'Pick a map point or turn off map';
          setState(() => _error = msg);
          _scrollToKey(_coordsKey);
          return false;
        }
        return _formKeyCoords.currentState?.validate() ?? false;
      case 3:
        return _formKeyLocation.currentState?.validate() ?? false;
      case 4:
        _refreshAutoTitle();
        return _formKeyPricing.currentState?.validate() ?? false;
      case 5:
        if (_isLand && _streetCount != null && _streetCount! > 0) {
          final widths = _buildStreetWidths();
          if (widths.length < _streetCount!) {
            final msg = _isAr ? 'أدخل عرض كل شارع' : 'Enter each street width';
            setState(() => _error = msg);
            return false;
          }
        }
        if (_showParkingYearRow && _yearBuilt == null) {
          setState(() => _error = _isAr
              ? 'سنة البناء مطلوبة'
              : 'Year built is required');
          return false;
        }
        return _formKeyDetails.currentState?.validate() ?? false;
      case 6:
        if (_requiresExternalLicenseBundle) {
          if (_images.isEmpty) {
            final msg = _isAr
                ? 'أضف صور العقار (رخصة خارجية)'
                : 'Add property photos (external license)';
            setState(() => _error = msg);
            _scrollToKey(_listingMediaKey);
            return false;
          }
          if (_videoUrl.text.trim().isEmpty) {
            final msg = _isAr
                ? 'أضف فيديو (رخصة خارجية)'
                : 'Add video (external license)';
            setState(() => _error = msg);
            _scrollToKey(_listingMediaKey);
            return false;
          }
          if ((_licensePdfStoragePath ?? '').trim().isEmpty) {
            final msg = _isAr ? 'أرفع PDF الرخصة' : 'Upload license PDF';
            setState(() => _error = msg);
            _scrollToKey(_listingMediaKey);
            return false;
          }
          return true;
        }
        if (_images.isEmpty && _videoUrl.text.trim().isEmpty) {
          if (!_requiresExternalLicenseBundle) {
            return true;
          }
          final msg = _isAr ? 'أضف فيديو أو صورة' : 'Add a video or photo';
          setState(() => _error = msg);
          _scrollToKey(_listingMediaKey);
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _scrollWizardStepToTop() {
    WizardStepNavigation.scrollToTop(_scrollCtrl);
  }

  void _wizardPrev() {
    final minStep = _marketingFlowActive ? 1 : 0;
    if (_wizardStep <= minStep) return;
    setState(() {
      _wizardStep--;
      _error = null;
    });
    unawaited(_persistListingDraft(showSnack: false));
    _scrollWizardStepToTop();
  }

  void _wizardNext() {
    if (!_validateWizardStep(_wizardStep)) return;
    if (_wizardStep < _kWizardLastStep) {
      setState(() {
        _wizardStep++;
        _error = null;
      });
      unawaited(_persistListingDraft(showSnack: false));
      _scrollWizardStepToTop();
      if (_marketingLicensedSplit &&
          _wizardPaneKind(_wizardStep) == 2 &&
          _useMapCoords) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_openMapPicker(kingdomOverview: false));
        });
      }
    }
  }

  Widget _buildPropertyFormSlice(
    AddPropertyFormSlice slice,
    GlobalKey<FormState> formKey,
  ) {
    return _FormCard(
      isAr: _isAr,
      formKey: formKey,
      saving: _saving || _picking || _uploadingVideo || _uploadingLicensePdf,
      slice: slice,
      wizardPaneKind: _wizardPaneKind(_wizardStep),
      marketingSimplifiedForm: _marketingSimplifiedForm,
      primaryPurposeGroup: _primaryPurposeGroup,
      onPrimaryPurposeGroupChanged: (v) => setState(() {
        _primaryPurposeGroup = v;
        _subPurposeCode = null;
        _syncPurposeFromPrimaryGroup();
      }),
      propertyCategory: _propertyCategory,
      onPropertyCategoryChanged: (v) => setState(() {
        _propertyCategory = v;
        _applyPropertyCategoryDefaults();
      }),
      subPurposeCode: _subPurposeCode,
      onSubPurposeCodeChanged: (v) => setState(() {
        _subPurposeCode = v;
        _syncPurposeFromPrimaryGroup();
      }),
      propertyHasObligations: _propertyHasObligations,
      onPropertyHasObligationsChanged: (v) =>
          setState(() => _propertyHasObligations = v),
      obligationsDetail: _obligationsDetail,
      autoFillTitle: _marketingFlowActive,
      locationsLoading: _locationsLoading,
      regionController: _region,
      governorateController: _governorate,
      cityController: _city,
      locationController: _location,
      addressLineController: _addressLine,
      regionManual: _regionManual,
      governorateManual: _governorateManual,
      cityManual: _cityManual,
      selectedRegion: _selectedRegion,
      selectedGovernorate: _selectedGovernorate,
      selectedCity: _selectedCity,
      regionOptions: _regionOptions,
      governorateOptions: _currentGovernorateOptions,
      cityOptions: _currentCityOptions,
      onRegionSelected: _selectRegionValue,
      onGovernorateSelected: _selectGovernorateValue,
      onCitySelected: _selectCityValue,
      onRegionManualChanged: (v) => setState(() {
        _regionManual = v;
        if (v) _selectedRegion = null;
      }),
      onGovernorateManualChanged: (v) => setState(() {
        _governorateManual = v;
        if (v) _selectedGovernorate = null;
      }),
      onCityManualChanged: (v) => setState(() {
        _cityManual = v;
        if (v) _selectedCity = null;
      }),
      type: _type,
      purpose: _purpose,
      purposeTypes: _purposeTypes,
      onTypeChanged: (v) => setState(() {
        final wasLand = _isLand;
        _type = v;
        if (wasLand && !_isLand) _clearLandOnlyFormFields();
        _maybeSuggestSmartTitle();
      }),
      onPurposeChanged: (v) => setState(() {
        _purpose = v;
        _maybeSuggestSmartTitle();
      }),
      priceOnSum: _priceOnSum,
      onPriceOnSumChanged: (v) => setState(() {
        _priceOnSum = v;
        if (v) {
          _negotiable = true;
          if (_price.text.trim().isEmpty) _price.text = '0';
        }
      }),
      acceptsMortgageFinance: _acceptsMortgageFinance,
      onAcceptsMortgageFinanceChanged: (v) =>
          setState(() => _acceptsMortgageFinance = v),
      propertyAgeBucket: _propertyAgeBucket,
      onPropertyAgeBucketChanged: (v) =>
          setState(() => _propertyAgeBucket = v),
      onSuggestSmartTitle: () => setState(() {
        _maybeSuggestSmartTitle(force: true);
      }),
      usageResidential: _usageResidential,
      usageCommercial: _usageCommercial,
      onUsageResidentialChanged: (v) => setState(() => _usageResidential = v),
      onUsageCommercialChanged: (v) => setState(() => _usageCommercial = v),
      title: _title,
      desc: _desc,
      area: _area,
      price: _price,
      areaUnit: _areaUnit,
      onAreaUnitChanged: (u) => setState(() => _areaUnit = u),
      computedPricePerSqm: _computedPricePerSqm(),
      priceIncludesVat: _priceIncludesVat,
      onPriceIncludesVatChanged: (v) => setState(() => _priceIncludesVat = v),
      commissionKind: _commissionKind,
      onCommissionKindChanged: (v) => setState(() {
        _commissionKind = v;
        if (v != 'fixed') _commissionFixedCtrl.clear();
      }),
      commissionFixedCtrl: _commissionFixedCtrl,
      liveInvoice: _buildLiveInvoice(),
      currency: _currency,
      negotiable: _negotiable,
      onCurrencyChanged: (v) => setState(() => _currency = v),
      onNegotiableChanged: (v) => setState(() => _negotiable = v),
      isAuction: _isAuction,
      currentBid: _currentBid,
      onAuctionChanged: (v) => setState(() {
        _isAuction = v;
        if (!v) _currentBid.clear();
      }),
      bedrooms: _bedrooms,
      bathrooms: _bathrooms,
      parkingSpots: _parkingSpots,
      furnished: _furnished,
      yearBuilt: _yearBuilt,
      floor: _floor,
      totalFloors: _totalFloors,
      onBedroomsChanged: (v) => setState(() => _bedrooms = v),
      onBathroomsChanged: (v) => setState(() => _bathrooms = v),
      onParkingChanged: (v) => setState(() => _parkingSpots = v),
      onFurnishedChanged: (v) => setState(() => _furnished = v),
      onYearBuiltChanged: (v) => setState(() => _yearBuilt = v),
      onFloorChanged: (v) => setState(() => _floor = v),
      onTotalFloorsChanged: (v) => setState(() => _totalFloors = v),
      amenities: _amenities,
      onAmenityToggle: (k, v) => setState(() => _amenities[k] = v),
      requiresDeed: _requiresDeed,
      deedNumber: _deedNumber,
      deedIssuer: _deedIssuer,
      deedDate: _deedDate,
      onPickDeedDate: _pickDeedDate,
      onClearDeedDate: () => setState(() => _deedDate = null),
      buildingNumber: _buildingNumber,
      showBuildingNumber: _showBuildingNumber,
      virtualTourUrl: _virtualTourUrl,
      availabilityDate: _availabilityDate,
      onPickAvailability: _pickAvailabilityDate,
      onClearAvailability: () => setState(() => _availabilityDate = null),
      livingRooms: _livingRooms,
      kitchens: _kitchens,
      hasElevator: _hasElevator,
      independentEntrance: _independentEntrance,
      hasCentralAc: _hasCentralAc,
      hasSplitAc: _hasSplitAc,
      onLivingRoomsChanged: (v) => setState(() => _livingRooms = v),
      onKitchensChanged: (v) => setState(() => _kitchens = v),
      onHasElevatorChanged: (v) => setState(() => _hasElevator = v),
      onIndependentEntranceChanged: (v) =>
          setState(() => _independentEntrance = v),
      onHasCentralAcChanged: (v) => setState(() => _hasCentralAc = v),
      onHasSplitAcChanged: (v) => setState(() => _hasSplitAc = v),
      majlisCount: _majlisCount,
      annexCount: _annexCount,
      hasGarden: _hasGarden,
      hasPool: _hasPool,
      hasCourtyard: _hasCourtyard,
      carEntrance: _carEntrance,
      internalStair: _internalStair,
      separateApartment: _separateApartment,
      hasDriverRoom: _hasDriverRoom,
      hasMaidRoom: _hasMaidRoom,
      hasStorageRoom: _hasStorageRoom,
      onMajlisCountChanged: (v) => setState(() => _majlisCount = v),
      onAnnexCountChanged: (v) => setState(() => _annexCount = v),
      onHasGardenChanged: (v) => setState(() => _hasGarden = v),
      onHasPoolChanged: (v) => setState(() => _hasPool = v),
      onHasCourtyardChanged: (v) => setState(() => _hasCourtyard = v),
      onCarEntranceChanged: (v) => setState(() => _carEntrance = v),
      onInternalStairChanged: (v) => setState(() => _internalStair = v),
      onSeparateApartmentChanged: (v) => setState(() => _separateApartment = v),
      onHasDriverRoomChanged: (v) => setState(() => _hasDriverRoom = v),
      onHasMaidRoomChanged: (v) => setState(() => _hasMaidRoom = v),
      onHasStorageRoomChanged: (v) => setState(() => _hasStorageRoom = v),
      floorsCount: _floorsCount,
      unitsCount: _unitsCount,
      plotArea: _plotArea,
      hasLoadingDock: _hasLoadingDock,
      hasCrane: _hasCrane,
      projectType: _projectType,
      onFloorsCountChanged: (v) => setState(() => _floorsCount = v),
      onUnitsCountChanged: (v) => setState(() => _unitsCount = v),
      onPlotAreaChanged: (v) => setState(() => _plotArea = v),
      onHasLoadingDockChanged: (v) => setState(() => _hasLoadingDock = v),
      onHasCraneChanged: (v) => setState(() => _hasCrane = v),
      onProjectTypeChanged: (v) => setState(() => _projectType = v),
      landUse: _landUse,
      facade: _facade,
      streetCount: _streetCount,
      streetWidth1: _streetWidth1,
      streetWidth2: _streetWidth2,
      streetWidth3: _streetWidth3,
      streetWidth4: _streetWidth4,
      isCornerLand: _isCornerLand,
      planNumber: _planNumber,
      parcelNumber: _parcelNumber,
      onLandUseChanged: (v) => setState(() => _landUse = v),
      onFacadeChanged: (v) => setState(() => _facade = v),
      onStreetCountChanged: (v) => setState(() => _streetCount = v),
      onIsCornerLandChanged: (v) => setState(() => _isCornerLand = v),
      isLand: _isLand,
      isProject: _isProject,
      isWarehouse: _isWarehouse,
      isBuilding: _isBuilding,
      showResidentialBedBath: _showResidentialBedBath,
      showParkingYearRow: _showParkingYearRow,
      showFurnishedRow: _showFurnishedRow,
      showFloorFieldsRow: _showFloorFieldsRow,
      districtManual: _districtManual,
      selectedDistrict: _selectedDistrict,
      districtOptions: _currentDistrictOptions,
      onDistrictSelected: _selectDistrictValue,
      onDistrictManualChanged: (v) => setState(() {
        _districtManual = v;
        if (v) _selectedDistrict = null;
      }),
      boundaryNorth: _boundaryNorth,
      boundarySouth: _boundarySouth,
      boundaryEast: _boundaryEast,
      boundaryWest: _boundaryWest,
    );
  }

  static String normalizeNumbers(String input) {
    const arabicIndic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const easternArabicIndic = [
      '۰',
      '۱',
      '۲',
      '۳',
      '۴',
      '۵',
      '۶',
      '۷',
      '۸',
      '۹'
    ];
    var out = input;
    for (int i = 0; i < 10; i++) {
      out = out.replaceAll(arabicIndic[i], i.toString());
      out = out.replaceAll(easternArabicIndic[i], i.toString());
    }
    return out;
  }

  double _parseDouble(String s) {
    final v = normalizeNumbers(s).trim().replaceAll(',', '');
    return double.tryParse(v) ?? 0;
  }

  double? _parseNullableDouble(String s) {
    final v = normalizeNumbers(s).trim().replaceAll(',', '');
    if (v.isEmpty) return null;
    return double.tryParse(v);
  }

  String _resolveOwnerId() {
    final user = _sb.auth.currentUser;
    return widget.userId.trim().isNotEmpty
        ? widget.userId.trim()
        : (user?.id ?? '');
  }

  Future<void> _loadSaudiLocations() async {
    setState(() => _locationsLoading = true);
    try {
      final all = await SaudiLocationsService.instance.loadAll();
      _governoratesByRegion.clear();
      _citiesByGovernorate.clear();

      final regions = <String>{};
      final governoratesByRegion = <String, Set<String>>{};
      final citiesByGovernorate = <String, Set<String>>{};

      for (final item in all) {
        final region = _isAr ? item.regionAr.trim() : item.regionEn.trim();
        final governorate = _isAr
            ? (item.governorateAr?.trim() ?? '')
            : (item.governorateEn?.trim() ?? '');
        final city = _isAr ? item.cityAr.trim() : item.cityEn.trim();

        if (region.isEmpty || city.isEmpty) continue;

        regions.add(region);

        if (governorate.isNotEmpty) {
          governoratesByRegion
              .putIfAbsent(region, () => <String>{})
              .add(governorate);
          citiesByGovernorate
              .putIfAbsent(governorate, () => <String>{})
              .add(city);
        } else {
          governoratesByRegion
              .putIfAbsent(region, () => <String>{})
              .add(region);
          citiesByGovernorate.putIfAbsent(region, () => <String>{}).add(city);
        }
      }

      final sortedRegions = regions.toList()..sort();
      final sortedGovernoratesByRegion = <String, List<String>>{};
      for (final entry in governoratesByRegion.entries) {
        final list = entry.value.toList()..sort();
        sortedGovernoratesByRegion[entry.key] = list;
      }

      final sortedCitiesByGovernorate = <String, List<String>>{};
      for (final entry in citiesByGovernorate.entries) {
        final list = entry.value.toList()..sort();
        sortedCitiesByGovernorate[entry.key] = list;
      }

      Map<String, List<String>> distMap = {};
      try {
        distMap =
            await SaudiDistrictsService.instance.loadMergedWithCityAliases();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _regionOptions
          ..clear()
          ..addAll(sortedRegions);
        _governoratesByRegion
          ..clear()
          ..addAll(sortedGovernoratesByRegion);
        _citiesByGovernorate
          ..clear()
          ..addAll(sortedCitiesByGovernorate);
        _districtsByCity = distMap;
        _locationsLoading = false;
        _syncLocationSelectionsFromControllers();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationsLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _restoreTempCoords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'coords_temp_${widget.userId}';
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final lat = (json['lat'] as num?)?.toDouble();
      final lng = (json['lng'] as num?)?.toDouble();
      if (!mounted) return;
      setState(() {
        _lat = lat;
        _lng = lng;
        if (lat != null) _latCtrl.text = lat.toStringAsFixed(6);
        if (lng != null) _lngCtrl.text = lng.toStringAsFixed(6);
        if (lat != null && lng != null) _useMapCoords = true;
      });
      if (_lat != null && _lng != null) {
        await _fillLocationFromNearest();
      }
    } catch (_) {}
  }

  /// REGA / FAL path satisfied — enables verified marketer **direct publish** to home.
  bool _regaVerificationSatisfied() {
    final flow = widget.marketingFlow;
    if (flow != null) {
      if (flow.listingRequestOnly) return false;
      if (flow.publishToHomeFeed) return _licensedAdPayloadComplete();
      return false;
    }
    if (_regaVerifyOk == true) return true;
    final fv = _regaPayloadForInsert['fal_license_verify'];
    if (fv is Map && fv['valid'] == true) return true;
    return _licensedAdPayloadComplete();
  }

  bool _licensedAdPayloadComplete() {
    String digits(dynamic raw) =>
        raw.toString().replaceAll(RegExp(r'\D'), '');
    final ad = digits(_regaPayloadForInsert['rega_ad_license_number']);
    final fal = digits(_regaPayloadForInsert['fal_broker_license_number']);
    return ad.length == 10 && fal.length == 10;
  }

  bool get _forceListingRequestPath =>
      widget.marketingFlow?.listingRequestOnly == true;

  Future<bool> _isVerifiedMarketer(String userId) async {
    // الجدول المعتمد: marketer_profiles فقط (لا marketers / is_marketer_verified).
    try {
      final m = await _sb
          .from('marketer_profiles')
          .select('is_verified')
          .eq('user_id', userId)
          .maybeSingle();
      if (m == null) return false;
      final v = m['is_verified'];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v.toLowerCase() == 'true' || v == '1';
    } catch (_) {}
    return false;
  }

  bool get _hasUploadedVideo => _videoUrl.text.trim().isNotEmpty;

  Future<void> _showPickImagesMenu() async {
    if (_saving || _picking || _uploadingVideo) return;
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await _pickImages(source: _PickSource.files);
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
                    _pickImages(source: _PickSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: Text(_isAr ? 'الكاميرا' : 'Camera'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImages(source: _PickSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text(_isAr ? 'اختيار من الملفات' : 'Choose files'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImages(source: _PickSource.files);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// صور + فيديو من شريط التطبيق أو كبداية الصفحة.
  Future<void> _showPickMediaMenu() async {
    if (_saving || _picking || _uploadingVideo) return;
    if (!mounted) return;

    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
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
                    title: Text(_isAr ? 'صور من الملفات' : 'Images from files'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImages(source: _PickSource.files);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.video_file_outlined),
                    title: Text(_isAr ? 'فيديو من ملف' : 'Video from file'),
                    onTap: () {
                      Navigator.pop(ctx);
                      if (_hasUploadedVideo) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              _isAr
                                  ? 'يمكن إضافة فيديو واحد فقط'
                                  : 'Only one video allowed',
                            ),
                          ),
                        );
                      } else {
                        _pickVideoFromFiles();
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

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
                  title: Text(_isAr ? 'صور من المعرض' : 'Images from gallery'),
                  subtitle: Text(_isAr ? 'عدة صور' : 'Multiple images'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImages(source: _PickSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: Text(_isAr ? 'تصوير صورة' : 'Take photo'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImages(source: _PickSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text(_isAr ? 'صور من الملفات' : 'Images from files'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImages(source: _PickSource.files);
                  },
                ),
                const Divider(height: 24),
                ListTile(
                  leading: const Icon(Icons.video_library_outlined),
                  title: Text(_isAr ? 'فيديو من المعرض' : 'Video from gallery'),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (_hasUploadedVideo) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text(
                            _isAr
                                ? 'يمكن إضافة فيديو واحد فقط'
                                : 'Only one video allowed',
                          ),
                        ),
                      );
                    } else {
                      _pickVideoFromGallery();
                    }
                  },
                ),
                if (!kIsWeb)
                  ListTile(
                    leading: const Icon(Icons.videocam_outlined),
                    title: Text(_isAr ? 'تسجيل فيديو' : 'Record video'),
                    onTap: () {
                      Navigator.pop(ctx);
                      if (_hasUploadedVideo) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              _isAr
                                  ? 'يمكن إضافة فيديو واحد فقط'
                                  : 'Only one video allowed',
                            ),
                          ),
                        );
                      } else {
                        _pickVideoFromCamera();
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.video_file_outlined),
                  title: Text(_isAr ? 'فيديو من ملف' : 'Video from file'),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (_hasUploadedVideo) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text(
                            _isAr
                                ? 'يمكن إضافة فيديو واحد فقط'
                                : 'Only one video allowed',
                          ),
                        ),
                      );
                    } else {
                      _pickVideoFromFiles();
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _clearUploadedVideo() => setState(() => _videoUrl.clear());

  Future<void> _pickImages({required _PickSource source}) async {
    if (_saving || _picking) return;

    final nativeMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final t = AppLocalizations.of(context);
    if (nativeMobile && t != null) {
      if (source == _PickSource.gallery) {
        final ok = await RuntimePermissionHelper.ensurePhotos(context, t: t);
        if (!ok || !mounted) return;
      } else if (source == _PickSource.camera) {
        final ok = await RuntimePermissionHelper.ensureCamera(context, t: t);
        if (!ok || !mounted) return;
      }
    }

    setState(() {
      _picking = true;
      _error = null;
    });
    suspendAutoLock.value = true;
    try {
      final newOnes = <_PickedImage>[];
      if (source == _PickSource.files ||
          kIsWeb ||
          !(defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        final res = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          type: FileType.image,
          withData: true,
        );
        if (!mounted) return;
        if (res != null) {
          for (final f in res.files) {
            final b = f.bytes;
            final n = f.name;
            if (b != null && n.isNotEmpty) {
              newOnes.add(_PickedImage(name: n, bytes: b));
            }
          }
        }
      } else {
        final picker = ImagePicker();
        if (source == _PickSource.gallery) {
          final files = await picker.pickMultiImage(imageQuality: 90);
          if (!mounted) return;
          for (final x in files) {
            final b = await x.readAsBytes();
            final n = x.name.isNotEmpty
                ? x.name
                : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
            newOnes.add(_PickedImage(name: n, bytes: b));
          }
        } else if (source == _PickSource.camera) {
          final x = await picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 90,
          );
          if (!mounted) return;
          if (x != null) {
            final b = await x.readAsBytes();
            final n = x.name.isNotEmpty
                ? x.name
                : 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg';
            newOnes.add(_PickedImage(name: n, bytes: b));
          }
        }
      }
      if (!mounted) return;
      setState(() {
        if (newOnes.isNotEmpty) _images.addAll(newOnes);
        _picking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _error = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content:
              Text(_isAr ? 'فشل اختيار الصور: $e' : 'Image pick failed: $e'),
        ),
      );
    } finally {
      suspendAutoLock.value = false;
    }
  }

  void _removeImageAt(int i) => setState(() => _images.removeAt(i));

  void _moveImage(int from, int to) => setState(() {
        final item = _images.removeAt(from);
        _images.insert(to, item);
      });

  Future<void> _openMapPicker({bool kingdomOverview = false}) async {
    LatLng? initial;
    if (_lat != null && _lng != null) {
      initial = LatLng(_lat!, _lng!);
    } else {
      final city = (_selectedCity ?? _city.text).trim();
      if (city.isNotEmpty) {
        final loc = await SaudiLocationsService.instance.findByCity(city);
        if (loc != null && loc.lat != 0 && loc.lng != 0) {
          initial = LatLng(loc.lat, loc.lng);
        }
      }
    }
    final res = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => MapPickerPage(
          initial: initial,
          isAr: _isAr,
          kingdomOverview: kingdomOverview && initial == null,
          pinTitle: _title.text.trim().isEmpty
              ? (_isAr ? 'إعلان عقاري جديد' : 'New property listing')
              : _title.text.trim(),
          pinSubtitle: (_selectedCity ?? _city.text).trim(),
          pinKindLabel: _isAr ? 'إعلان عقاري' : 'Property listing',
          pinAmountLabel: _price.text.trim().isEmpty
              ? null
              : '${_price.text.trim()} ${_currency.toUpperCase() == 'SAR' ? AppMoney.saudiRiyalSignUnicode : _currency}',
        ),
      ),
    );
    if (!mounted || res == null) return;
    final lat = res['lat'];
    final lng = res['lng'];
    final approx = res['approximate'] == true;
    final metaCity = (res['city'] ?? '').toString().trim();
    final metaRegion = (res['region'] ?? '').toString().trim();
    final metaGov = (res['governorate'] ?? '').toString().trim();
    final metaDistrict = (res['district'] ?? '').toString().trim();
    setState(() {
      _locationIsApproximate = approx;
      _lat = (lat is num)
          ? lat.toDouble()
          : double.tryParse(lat?.toString() ?? '');
      _lng = (lng is num)
          ? lng.toDouble()
          : double.tryParse(lng?.toString() ?? '');
      _latCtrl.text = _lat?.toStringAsFixed(6) ?? '';
      _lngCtrl.text = _lng?.toStringAsFixed(6) ?? '';
      _error = null;
    });
    if (_lat != null && _lng != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'coords_temp_${widget.userId}',
        jsonEncode({
          'lat': _lat,
          'lng': _lng,
          'approximate': _locationIsApproximate,
        }),
      );
      if (metaCity.isNotEmpty || metaRegion.isNotEmpty) {
        await _applyResolvedLocation(
          region: metaRegion,
          governorate: metaGov,
          city: metaCity,
          district: metaDistrict,
        );
      } else {
        await _fillLocationFromNearest();
      }
      _maybeSuggestSmartTitle();
    }
  }

  Future<void> _fillLocationFromNearest() async {
    if (_lat == null || _lng == null) return;
    final info = await SaudiLocationsService.instance.findNearest(_lat!, _lng!);
    if (!mounted || info == null) return;
    final r = _isAr ? info.regionAr.trim() : info.regionEn.trim();
    final rawG =
        _isAr ? info.governorateAr?.trim() : info.governorateEn?.trim();
    final g = (rawG != null && rawG.isNotEmpty) ? rawG : '';
    final c = _isAr ? info.cityAr.trim() : info.cityEn.trim();
    await _applyResolvedLocation(
      region: r,
      governorate: g.isNotEmpty ? g : c,
      city: c,
      district: '',
    );
  }

  /// يضبط الهرم منطقة→محافظة→مدينة→حي بحيث تظهر في القوائم (لا تبقى المنطقة فقط).
  Future<void> _applyResolvedLocation({
    required String region,
    required String governorate,
    required String city,
    required String district,
  }) async {
    final r = region.trim();
    final gIn = governorate.trim();
    final c = city.trim();
    final d = district.trim();
    if (!mounted) return;

    setState(() {
      _regionManual = false;
      _governorateManual = false;
      _cityManual = false;
      _districtManual = false;

      if (r.isNotEmpty) {
        _selectedRegion = r;
        _region.text = r;
      }

      final govList = r.isEmpty
          ? const <String>[]
          : (_governoratesByRegion[r] ?? const <String>[]);
      var g = gIn;
      if (g.isEmpty && c.isNotEmpty && govList.contains(c)) {
        g = c;
      }
      if (g.isEmpty && govList.length == 1) {
        g = govList.first;
      }
      if (g.isNotEmpty) {
        if (govList.contains(g)) {
          _selectedGovernorate = g;
          _governorate.text = g;
        } else {
          _governorateManual = true;
          _selectedGovernorate = null;
          _governorate.text = g;
        }
      }

      final govKey = (_selectedGovernorate ?? _governorate.text).trim();
      final cityList = govKey.isEmpty
          ? const <String>[]
          : (_citiesByGovernorate[govKey] ?? const <String>[]);
      if (c.isNotEmpty) {
        if (cityList.contains(c)) {
          _selectedCity = c;
          _city.text = c;
        } else {
          // أظهر المدينة كنص حتى لو لم تكن في القائمة بعد.
          _cityManual = true;
          _selectedCity = null;
          _city.text = c;
        }
      }

      _selectedDistrict = null;
      _location.clear();
      _syncLocationSelectionsFromControllers();
    });

    final cityKey = (_selectedCity ?? _city.text).trim();
    if (cityKey.isEmpty) return;

    List<String> districts = _districtsByCity[cityKey] ?? const [];
    if (districts.isEmpty) {
      districts =
          await SaudiDistrictsService.instance.districtsForCity(cityKey);
      if (!mounted) return;
      if (districts.isNotEmpty) {
        setState(() {
          _districtsByCity = Map<String, List<String>>.from(_districtsByCity)
            ..[cityKey] = districts;
        });
      }
    }

    if (d.isNotEmpty) {
      String? match;
      for (final x in districts) {
        if (x == d || x.contains(d) || d.contains(x)) {
          match = x;
          break;
        }
      }
      if (match != null) {
        await _selectDistrictValue(match);
      } else {
        setState(() {
          _districtManual = true;
          _selectedDistrict = null;
          _location.text = d;
        });
      }
    } else if (districts.length == 1) {
      await _selectDistrictValue(districts.first);
    }
  }

  /// عنوان إعلان ذكي من النوع + الغرض + المدينة/الحي (عندما يكون العنوان فارغاً).
  void _maybeSuggestSmartTitle({bool force = false}) {
    if (!force && _title.text.trim().isNotEmpty) return;
    final typeLabel = PropertyTypeCatalog.label(_type, _isAr);
    final purpose = _purpose.trim().toLowerCase();
    final purposeBit = purpose.contains('rent')
        ? (_isAr ? 'للإيجار' : 'for rent')
        : (purpose.contains('auction')
            ? (_isAr ? 'للمزاد' : 'for auction')
            : (_isAr ? 'للبيع' : 'for sale'));
    final city = (_selectedCity ?? _city.text).trim();
    final district = (_selectedDistrict ?? _location.text).trim();
    final suggested = PropertyListingDisplay.composeListingHeadline(
      typeLabel: typeLabel,
      purposeBit: purposeBit,
      city: city,
      district: district.isNotEmpty && district != city ? district : null,
      isAr: _isAr,
    );
    if (suggested.trim().isEmpty) return;
    _title.text = suggested.trim();
  }

  Future<void> _selectDistrictValue(String? value) async {
    if (value == null) return;
    if (value == _kManualOptionValue) {
      setState(() {
        _districtManual = true;
        _selectedDistrict = null;
        _location.clear();
      });
      return;
    }
    setState(() {
      _districtManual = false;
      _selectedDistrict = value;
      _location.text = value;
      _maybeSuggestSmartTitle();
    });
  }

  Future<bool> _videoPassesUploadPolicy({
    String? path,
    Uint8List? bytes,
  }) async {
    if (bytes != null && bytes.length > _kMaxVideoBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              _isAr
                  ? 'حجم الفيديو يتجاوز الحد المسموح (50 م.ب)'
                  : 'Video exceeds maximum size (50 MB)',
            ),
          ),
        );
      }
      return false;
    }
    if (!kIsWeb && path != null && path.isNotEmpty) {
      final dur = await readVideoDurationFromPath(path);
      if (dur != null && dur.inSeconds > _kMaxVideoSeconds) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(
                _isAr
                    ? 'مدة الفيديو يجب ألا تتجاوز دقيقتين'
                    : 'Video must be at most 2 minutes',
              ),
            ),
          );
        }
        return false;
      }
    }
    return true;
  }

  void _onLatChanged(String value) =>
      setState(() => _lat = _parseNullableDouble(value));

  void _onLngChanged(String value) =>
      setState(() => _lng = _parseNullableDouble(value));

  Future<void> _loadOwnerName() async {
    try {
      final ownerId = _resolveOwnerId();
      if (ownerId.isEmpty) return;
      final up = await _sb
          .from('users_profiles')
          .select(
              'first_name_ar, fourth_name_ar, first_name_en, fourth_name_en, username, email')
          .eq('user_id', ownerId)
          .maybeSingle();
      if (up != null) {
        if (_isAr) {
          _ownerFirstName = (up['first_name_ar'] as String?)?.trim();
          _ownerLastName = (up['fourth_name_ar'] as String?)?.trim();
        } else {
          _ownerFirstName = (up['first_name_en'] as String?)?.trim();
          _ownerLastName = (up['fourth_name_en'] as String?)?.trim();
        }
        if ((_ownerFirstName == null || _ownerFirstName!.isEmpty) &&
            (_ownerLastName == null || _ownerLastName!.isEmpty)) {
          _ownerFirstName = (up['username'] as String?)?.trim();
          if (_ownerFirstName == null || _ownerFirstName!.isEmpty) {
            _ownerFirstName = (up['email'] as String?)?.trim();
          }
        }
      }
      if (_ownerFirstName == null || _ownerFirstName!.isEmpty) {
        Map<String, dynamic>? p;
        try {
          p = await _sb
              .from('profiles')
              .select('full_name, phone')
              .eq('user_id', ownerId)
              .maybeSingle();
        } catch (_) {
          try {
            p = await _sb
                .from('profiles')
                .select('full_name, phone')
                .eq('id', ownerId)
                .maybeSingle();
          } catch (_) {
            p = null;
          }
        }
        if (p != null) {
          final name = (p['full_name'] ?? p['phone'])?.toString();
          if (name != null && name.trim().isNotEmpty) {
            _ownerFirstName = name.trim();
          }
        }
      }

      _marketerPublishName = null;
      final verified = await _isVerifiedMarketer(ownerId);
      if (verified) {
        try {
          final mp = await _sb
              .from('marketer_profiles')
              .select('full_name_ar, full_name_en, full_name')
              .eq('user_id', ownerId)
              .maybeSingle();
          if (mp != null) {
            final n = _isAr
                ? (mp['full_name_ar'] ?? mp['full_name_en'] ?? mp['full_name'])
                : (mp['full_name_en'] ?? mp['full_name_ar'] ?? mp['full_name']);
            final t = n?.toString().trim();
            if (t != null && t.isNotEmpty) {
              _marketerPublishName = t;
            }
          }
        } catch (_) {}
      }

      if (mounted) setState(() {});
      unawaited(_loadPublisherIdentityPrefs());
    } catch (_) {}
  }

  Future<void> _loadPublisherIdentityPrefs() async {
    try {
      await PublisherIdentityPrefs.instance.ensureLoaded();
      if (!mounted) return;
      final id = PublisherIdentityPrefs.instance;
      setState(() {
        _pubNameSource = id.nameSource;
        _pubPhoneSource = id.phoneSource;
        _publishPresenceOnCards = id.publishPresenceOnCards;
        _officialNameCached = id.officialName(isAr: _isAr);
        _displayAliasCached = id.aliasName(isAr: _isAr);
        _primaryPhoneCached = id.primaryPhone;
        _secondaryPhoneCached = id.secondaryPhone;
      });
    } catch (_) {}
  }

  /// عمود location = الحي فقط (المحافظة في عمود governorate)
  String _composeLocationForDb() => _location.text.trim();

  /// يطابق القيم المخزّنة في الحقول مع عناصر القوائم بعد تحميل JSON (يصلح ظهور قوائم فارغة).
  void _syncLocationSelectionsFromControllers() {
    final r = _region.text.trim();
    if (r.isNotEmpty && _regionOptions.contains(r)) {
      _regionManual = false;
      _selectedRegion = r;
    }
    final regKey = (_selectedRegion ?? _region.text).trim();
    if (regKey.isEmpty) return;
    final govList = _governoratesByRegion[regKey] ?? const [];
    final g = _governorate.text.trim();
    if (g.isNotEmpty && govList.contains(g)) {
      _governorateManual = false;
      _selectedGovernorate = g;
    }
    final govKey = (_selectedGovernorate ?? _governorate.text).trim();
    if (govKey.isEmpty) return;
    final cityList = _citiesByGovernorate[govKey] ?? const [];
    final c = _city.text.trim();
    if (c.isNotEmpty && cityList.contains(c)) {
      _cityManual = false;
      _selectedCity = c;
    }
  }

  Future<void> _selectRegionValue(String? value) async {
    if (value == null) return;
    if (value == _kManualOptionValue) {
      setState(() {
        _regionManual = true;
        _selectedRegion = null;
        _region.clear();
        _selectedGovernorate = null;
        _governorate.clear();
        _governorateManual = true;
        _selectedCity = null;
        _city.clear();
        _cityManual = true;
        _selectedDistrict = null;
        _districtManual = false;
        _location.clear();
      });
      return;
    }
    setState(() {
      _regionManual = false;
      _selectedRegion = value;
      _region.text = value;
      _selectedGovernorate = null;
      _governorate.clear();
      _governorateManual = false;
      _selectedCity = null;
      _city.clear();
      _cityManual = false;
      _selectedDistrict = null;
      _districtManual = false;
      _location.clear();
    });
    final opts = _governoratesByRegion[value] ?? const [];
    if (opts.length == 1) {
      await _selectGovernorateValue(opts.first);
    }
  }

  Future<void> _selectGovernorateValue(String? value) async {
    if (value == null) return;
    if (value == _kManualOptionValue) {
      setState(() {
        _governorateManual = true;
        _selectedGovernorate = null;
        _governorate.clear();
        _selectedCity = null;
        _city.clear();
        _cityManual = true;
        _selectedDistrict = null;
        _districtManual = false;
        _location.clear();
      });
      return;
    }
    setState(() {
      _governorateManual = false;
      _selectedGovernorate = value;
      _governorate.text = value;
      _selectedCity = null;
      _city.clear();
      _cityManual = false;
      _selectedDistrict = null;
      _districtManual = false;
      _location.clear();
    });
    final cities = _citiesByGovernorate[value] ?? const [];
    if (cities.length == 1) {
      await _selectCityValue(cities.first);
    }
  }

  Future<void> _selectCityValue(String? value) async {
    if (value == null) return;
    if (value == _kManualOptionValue) {
      setState(() {
        _cityManual = true;
        _selectedCity = null;
        _city.clear();
        _selectedDistrict = null;
        _districtManual = false;
        _location.clear();
      });
      return;
    }
    setState(() {
      _cityManual = false;
      _selectedCity = value;
      _city.text = value;
      _selectedDistrict = null;
      _districtManual = false;
      _location.clear();
      _maybeSuggestSmartTitle();
    });

    final info = await SaudiLocationsService.instance.findByCity(value);
    if (!mounted || info == null) return;

    final regionValue = _isAr ? info.regionAr.trim() : info.regionEn.trim();
    if (_region.text.trim().isEmpty && regionValue.isNotEmpty) {
      setState(() {
        _regionManual = false;
        _selectedRegion = regionValue;
        _region.text = regionValue;
      });
    }

    final governorateValue =
        _isAr ? info.governorateAr?.trim() : info.governorateEn?.trim();
    if (governorateValue != null &&
        governorateValue.isNotEmpty &&
        _governorate.text.trim().isEmpty) {
      setState(() {
        _governorateManual = false;
        _selectedGovernorate = governorateValue;
        _governorate.text = governorateValue;
      });
    }

    if (!_useMapCoords) {
      final lat = info.lat;
      final lng = info.lng;
      if (lat != 0.0 || lng != 0.0) {
        setState(() {
          _lat = lat;
          _lng = lng;
          _latCtrl.text = lat.toStringAsFixed(6);
          _lngCtrl.text = lng.toStringAsFixed(6);
        });
      }
    }
  }

  Future<void> _tryAutoFillRegionAndCoordsFromCity() async {
    final cityValue = _city.text.trim();
    if (cityValue.isEmpty) return;
    final info = await SaudiLocationsService.instance.findByCity(cityValue);
    if (!mounted || info == null) return;

    final regionValue = _isAr ? info.regionAr.trim() : info.regionEn.trim();
    if (_region.text.trim().isEmpty && regionValue.isNotEmpty) {
      setState(() {
        _region.text = regionValue;
        _selectedRegion = regionValue;
        _regionManual = false;
      });
    }

    final governorateValue =
        _isAr ? info.governorateAr?.trim() : info.governorateEn?.trim();
    if (governorateValue != null &&
        governorateValue.isNotEmpty &&
        _governorate.text.trim().isEmpty) {
      setState(() {
        _governorate.text = governorateValue;
        _selectedGovernorate = governorateValue;
        _governorateManual = false;
      });
    }

    if (!_useMapCoords && (_lat == null || _lng == null)) {
      setState(() {
        _lat = info.lat;
        _lng = info.lng;
        _latCtrl.text = info.lat.toStringAsFixed(6);
        _lngCtrl.text = info.lng.toStringAsFixed(6);
      });
    }
  }

  Future<void> _showSuccessChoice({String? listingPublicCode}) async {
    final code = (listingPublicCode ?? '').trim();
    final choice = await showAdaptivePostPublishDialog(
      context: context,
      isAr: _isAr,
      title: _isAr ? 'تم نشر الإعلان' : 'Listing published',
      body: _isAr
          ? 'اختر الخطوة التالية.'
          : 'Choose the next step.',
      codeLine: code.isEmpty
          ? null
          : (_isAr
              ? 'رقم الإعلان: ${DisplayIds.tenDigit(code)}'
              : 'Listing no.: ${DisplayIds.tenDigit(code)}'),
      actions: [
        AdaptivePostPublishAction(
          id: 'back',
          label: _isAr ? 'الرئيسية' : 'Home',
          outlined: true,
        ),
        AdaptivePostPublishAction(
          id: 'again',
          label: _isAr ? 'إضافة إعلان' : 'Add listing',
          icon: Icons.add,
          filled: true,
        ),
      ],
    );
    if (!mounted) return;
    if (choice == 'again') {
      setState(() {
        _publishLock = false;
        _publishSucceeded = false;
      });
      _resetForm();
      final uid = _sb.auth.currentUser?.id ?? '';
      if (uid.isNotEmpty) {
        unawaited(
          WizardFormDraft.clear(namespace: _draftNamespace, userId: uid),
        );
      }
      return;
    }
    // الرئيسية (أو إغلاق الحوار): أغلِق صفحة الإضافة → اللوحة تضبط التبويب 0.
    await _popToDashboardHomeAfterPublish();
  }

  Future<void> _showRequestSuccess({
    required String requestId,
    String? listingRequestPublicCode,
  }) async {
    final code = (listingRequestPublicCode ?? '').trim();
    final choice = await showAdaptivePostPublishDialog(
      context: context,
      isAr: _isAr,
      title: _isAr ? 'تم إرسال طلب التسويق' : 'Request submitted',
      body: _isAr
          ? 'تم إرسال طلبك وسيتم مراجعته وتعيين مسوق له.'
          : 'Your request was sent. It will be reviewed and assigned to a marketer.',
      codeLine: code.isEmpty
          ? null
          : (_isAr
              ? 'رقم طلب التسويق: ${DisplayIds.tenDigit(code)}'
              : 'Marketing request no.: ${DisplayIds.tenDigit(code)}'),
      actions: [
        AdaptivePostPublishAction(
          id: 'home',
          label: _isAr ? 'الرئيسية' : 'Home',
        ),
        AdaptivePostPublishAction(
          id: 'status',
          label: _isAr ? 'متابعة الطلب' : 'Follow request',
          outlined: true,
        ),
        AdaptivePostPublishAction(
          id: 'again',
          label: _isAr ? 'إضافة إعلان' : 'Add listing',
          filled: true,
        ),
      ],
    );
    if (!mounted) return;
    if (choice == 'again') {
      setState(() {
        _publishLock = false;
        _publishSucceeded = false;
      });
      _resetForm();
      return;
    }
    if (choice == 'status') {
      setState(() {
        _publishLock = false;
        _publishSucceeded = true;
      });
      ActiveFormGuard.instance.unregister('add_property_listing');
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ListingRequestStatusPage(requestId: requestId, lang: widget.lang),
        ),
      );
      if (!mounted) return;
      await _popToDashboardHomeAfterPublish();
      return;
    }
    await _popToDashboardHomeAfterPublish();
  }

  void _resetForm() {
    setState(() {
      _title.clear();
      _desc.clear();
      _region.clear();
      _governorate.clear();
      _city.clear();
      _location.clear();
      _addressLine.clear();
      _buildingNumber.clear();
      _deedNumber.clear();
      _deedIssuer.clear();
      _deedDate = null;
      _selectedRegion = null;
      _selectedGovernorate = null;
      _selectedCity = null;
      _regionManual = false;
      _governorateManual = false;
      _cityManual = false;
      _area.clear();
      _price.clear();
      _commissionFixedCtrl.clear();
      _priceIncludesVat = null;
      _commissionKind = 'none';
      _usedDefaultCover = false;
      _currentBid.clear();
      _type = 'villa';
      _purpose = 'sale';
      _isAuction = false;
      _images.clear();
      _useMapCoords = false;
      _lat = null;
      _lng = null;
      _latCtrl.clear();
      _lngCtrl.clear();
      _usageResidential = false;
      _usageCommercial = false;
      _currency = 'SAR';
      _negotiable = false;
      _priceOnSum = false;
      _acceptsMortgageFinance = false;
      _noLegalObstacles = false;
      _advertiserRole = _advertiserRoleCode;
      _locationIsApproximate = false;
      _showOwnerNameOnCards = true;
      _propertyAgeBucket = null;
      _bedrooms = null;
      _bathrooms = null;
      _parkingSpots = null;
      _furnished = false;
      _yearBuilt = null;
      _floor = null;
      _totalFloors = null;
      _videoUrl.clear();
      _virtualTourUrl.clear();
      _availabilityDate = null;
      _livingRooms = null;
      _kitchens = null;
      _hasElevator = false;
      _independentEntrance = false;
      _hasCentralAc = false;
      _hasSplitAc = false;
      _majlisCount = null;
      _annexCount = null;
      _hasGarden = false;
      _hasPool = false;
      _hasCourtyard = false;
      _carEntrance = false;
      _internalStair = false;
      _separateApartment = false;
      _hasDriverRoom = false;
      _hasMaidRoom = false;
      _hasStorageRoom = false;
      _floorsCount = null;
      _unitsCount = null;
      _plotArea = null;
      _hasLoadingDock = false;
      _hasCrane = false;
      _projectType = null;
      _landUse = null;
      _facade = null;
      _streetCount = null;
      _streetWidth1.clear();
      _streetWidth2.clear();
      _streetWidth3.clear();
      _streetWidth4.clear();
      _isCornerLand = false;
      _planNumber.clear();
      _parcelNumber.clear();
      _boundaryNorth.clear();
      _boundarySouth.clear();
      _boundaryEast.clear();
      _boundaryWest.clear();
      _selectedDistrict = null;
      _districtManual = false;
      for (final k in _amenities.keys) {
        _amenities[k] = false;
      }
      _adLicenseSource = _AdLicenseSource.none;
      _propertyHasObligations = null;
      _obligationsDetail.clear();
      _extendedUsageNotes.clear();
      _licensePdfStoragePath = null;
      _uploadingLicensePdf = false;
      _areaUnit = ListingAreaUnit.m2;
      _regaFalLicenseNo.clear();
      _regaChecking = false;
      _regaVerifyBanner = null;
      _regaVerifyOk = null;
      _error = null;
      _termsAccepted = false;
      _wizardStep = _marketingFlowActive ? 1 : 0;
    });
  }

  Map<String, dynamic>? _amenitiesPayloadOrNull() {
    final selected = <String, bool>{};
    _amenities.forEach((k, v) {
      if (v) {
        if (_isLand) {
          const landAmenities = ['security', 'parking', 'wifi'];
          if (landAmenities.contains(k)) selected[k] = true;
        } else {
          selected[k] = true;
        }
      }
    });
    return selected.isEmpty ? null : selected;
  }

  List<double> _buildStreetWidths() {
    final raw = [
      _streetWidth1.text,
      _streetWidth2.text,
      _streetWidth3.text,
      _streetWidth4.text,
    ];
    final out = <double>[];
    for (final item in raw) {
      final d = _parseNullableDouble(item);
      if (d != null && d > 0) out.add(d);
    }
    return out;
  }

  Map<String, dynamic>? _buildExtraDetails() {
    final map = <String, dynamic>{};
    if (_isLand) {
      map.addAll({
        'land_use': _landUse,
        'facade': _facade,
        'street_count': _streetCount,
        'street_widths': _buildStreetWidths(),
        'is_corner': _isCornerLand,
        'plan_number': _planNumber.text.trim(),
        'parcel_number': _parcelNumber.text.trim(),
      });
    } else if (_isApartmentLike) {
      map.addAll({
        'living_rooms': _livingRooms,
        'kitchens': _kitchens,
        'has_elevator': _hasElevator,
        'independent_entrance': _independentEntrance,
        'has_central_ac': _hasCentralAc,
        'has_split_ac': _hasSplitAc,
      });
    } else if (_isVillaLike) {
      map.addAll({
        'living_rooms': _livingRooms,
        'kitchens': _kitchens,
        'majlis_count': _majlisCount,
        'annex_count': _annexCount,
        'has_garden': _hasGarden,
        'has_pool': _hasPool,
        'has_courtyard': _hasCourtyard,
        'car_entrance': _carEntrance,
        'internal_stair': _internalStair,
        'separate_apartment': _separateApartment,
        'has_driver_room': _hasDriverRoom,
        'has_maid_room': _hasMaidRoom,
        'has_storage_room': _hasStorageRoom,
      });
    } else if (_isBuilding) {
      map.addAll({
        'floors_count': _floorsCount,
        'units_count': _unitsCount,
        'has_elevator': _hasElevator,
        'independent_entrance': _independentEntrance,
      });
    } else if (_isWarehouse) {
      map.addAll({
        'has_loading_dock': _hasLoadingDock,
        'has_crane': _hasCrane,
        'parking_spots': _parkingSpots,
      });
    } else if (_isProject) {
      map.addAll({
        'project_type': _projectType,
        'plot_area': _plotArea,
        'units_count': _unitsCount,
      });
    } else if (_isOther) {
      map.addAll({'custom_type': _type});
    }
    map.removeWhere((k, v) =>
        v == null ||
        (v is String && v.trim().isEmpty) ||
        (v is List && v.isEmpty));
    return map.isEmpty ? null : map;
  }

  Map<String, dynamic> _listingGuidanceForInsert() {
    final hasV = _videoUrl.text.trim().isNotEmpty;
    final hasI = _images.isNotEmpty;
    final cover = (!hasV || !hasI)
        ? (hasV ? 'video' : 'image')
        : (_coverHeroIsVideo ? 'video' : 'image');
    final boundaries = <String, String>{};
    void putB(String k, TextEditingController c) {
      final t = c.text.trim();
      if (t.isNotEmpty) boundaries[k] = t;
    }

    putB('north', _boundaryNorth);
    putB('south', _boundarySouth);
    putB('east', _boundaryEast);
    putB('west', _boundaryWest);

    final out = <String, dynamic>{
      'cover_primary': cover,
      'usage': {
        'residential': _usageResidential,
        'commercial': _usageCommercial,
      },
      'ad_license_source': _adLicenseSource.name,
      'property_obligations': {
        'has_obligations': _propertyHasObligations,
        'detail': _obligationsDetail.text.trim(),
      },
      // — نسخة احتياطية لخيارات الفوترة داخل listing_guidance JSONB
      //   (مرآة للأعمدة الجديدة في الجدول؛ تُساعد عند قراءة سجلات قديمة أو نسخ احتياطية).
      'pricing': {
        'price_includes_vat': _priceIncludesVat ?? true,
        'vat_rate': _kVatRate,
        'marketing_commission_kind': _commissionKind,
        'marketing_commission_rate': _kMarketingCommissionRate,
        'marketing_commission_amount':
            _commissionKind == 'fixed' ? _fixedCommissionValue() : 0,
        'price_on_sum': _priceOnSum,
        'negotiable': _negotiable,
        'accepts_mortgage_finance': _acceptsMortgageFinance,
      },
      'deal_style': {
        'no_legal_obstacles': _noLegalObstacles,
        'advertiser_role': _advertiserRole,
        'location_is_approximate': _locationIsApproximate,
        'property_age_bucket': _propertyAgeBucket,
      },
    };
    final ext = _extendedUsageNotes.text.trim();
    if (ext.isNotEmpty) {
      out['extended_usage_notes'] = ext;
    }
    final pdf = _licensePdfStoragePath?.trim();
    if (pdf != null && pdf.isNotEmpty) {
      out['ad_license_pdf_path'] = pdf;
    }
    final ppm = _computedPricePerSqm();
    if (ppm != null && ppm > 0) {
      out['price_per_sqm'] = ppm;
    }
    if (boundaries.isNotEmpty) {
      out['parcel_boundaries'] = boundaries;
    }
    return out;
  }

  Map<String, dynamic> _buildPayload({
    required String ownerId,
    required bool hasLocationColumn,
    bool marketerDirectPublish = false,
  }) {
    final lat = _useMapCoords ? _parseNullableDouble(_latCtrl.text) : _lat;
    final lng = _useMapCoords ? _parseNullableDouble(_lngCtrl.text) : _lng;
    final areaStoredM2 = _areaValueInSquareMeters() ?? _parseDouble(_area.text);
    final publishedIso = DateTime.now().toUtc().toIso8601String();
    final payload = <String, dynamic>{
      'owner_id': ownerId,
      'title': _title.text.trim(),
      'description': _desc.text.trim(),
      'region': _region.text.trim(),
      'governorate': _governorate.text.trim(),
      'city': _city.text.trim(),
      'type': _type,
      'area': areaStoredM2,
      'price': _parseDouble(_price.text),
      'price_includes_vat': _priceIncludesVat ?? true,
      'vat_rate': _kVatRate,
      'marketing_commission_kind': _commissionKind,
      'marketing_commission_rate': _kMarketingCommissionRate,
      'marketing_commission_amount':
          _commissionKind == 'fixed' ? _fixedCommissionValue() : 0,
      'default_cover_used': _usedDefaultCover,
      'currency': _currency,
      'negotiable': _negotiable,
      'is_auction': _isAuction,
      'current_bid': _isAuction ? _parseDouble(_currentBid.text) : null,
      'views': 0,
      if (marketerDirectPublish) ...<String, dynamic>{
        'status': 'published',
        'workflow_stage': 'published',
        'published_by_marketer_id': ownerId,
        'published_at': publishedIso,
        'home_feed_suppressed': false,
      } else ...<String, dynamic>{
        'status': 'waiting_mediator',
        'workflow_stage': 'waiting_marketers',
        'home_feed_suppressed': true,
      },
      'latitude': lat,
      'longitude': lng,
      'video_url': _videoUrl.text.trim().isEmpty ? null : _videoUrl.text.trim(),
      'listing_guidance': _listingGuidanceForInsert(),
      'virtual_tour_url': _virtualTourUrl.text.trim().isEmpty
          ? null
          : _virtualTourUrl.text.trim(),
      'availability_date': _availabilityDate == null
          ? null
          : DateTime(
              _availabilityDate!.year,
              _availabilityDate!.month,
              _availabilityDate!.day,
            ).toIso8601String().substring(0, 10),
      'amenities': _amenitiesPayloadOrNull(),
      'address_line':
          _addressLine.text.trim().isEmpty ? null : _addressLine.text.trim(),
      'show_advertiser_name': _showOwnerNameOnCards,
      'owner_requests_public_name': _showOwnerNameOnCards,
      'publisher_public_name_source': _pubNameSource.name,
      'publisher_public_phone_source': _pubPhoneSource.name,
      'publisher_publish_presence': _publishPresenceOnCards,
      if (_showOwnerNameOnCards)
        'advertiser_public_name':
            PublisherIdentityPrefs.instance.resolvedPublicName(isAr: _isAr),
      if (_pubPhoneSource != PublicPhoneSource.hidden)
        'contact_phone':
            PublisherIdentityPrefs.instance.resolvedPublicPhone(),
    };
    final deedNorm = normalizeDeedNumber(_deedNumber.text);
    payload['deed_number'] = deedNorm.isEmpty ? null : deedNorm;
    payload['deed_date'] = _deedDate == null
        ? null
        : DateTime(_deedDate!.year, _deedDate!.month, _deedDate!.day)
            .toIso8601String()
            .substring(0, 10);
    payload['deed_issuer'] =
        _deedIssuer.text.trim().isEmpty ? null : _deedIssuer.text.trim();
    final bn = _buildingNumber.text.trim();
    payload['building_number'] =
        (_showBuildingNumber && bn.isNotEmpty) ? bn : null;
    if (hasLocationColumn) payload['location'] = _composeLocationForDb();
    if (_isProject) {
      payload['area'] = _plotArea ?? areaStoredM2;
    }
    if (_roomStatsForSave) {
      payload['bedrooms'] = _bedrooms;
      payload['bathrooms'] = _bathrooms;
    } else {
      payload['bedrooms'] = null;
      payload['bathrooms'] = null;
    }
    if (_showParkingYearRow) {
      payload['parking_spots'] = _parkingSpots;
      payload['year_built'] = _yearBuilt;
    } else {
      payload['parking_spots'] = null;
      payload['year_built'] = null;
    }
    if (_showFurnishedRow) {
      payload['furnished'] = _furnished;
    } else {
      payload['furnished'] = null;
    }
    if (_showFloorFields) {
      payload['floor'] = _floor;
      payload['total_floors'] = _totalFloors;
    } else {
      payload['floor'] = null;
      payload['total_floors'] = null;
    }
    payload['purpose'] = _purpose;
    if (_regaPayloadForInsert.isNotEmpty) {
      payload['rega_payload'] = _regaPayloadForInsert;
    }
    return payload;
  }

  Map<String, dynamic> _buildRequestPayload({required String ownerId}) {
    final lat = _useMapCoords ? _parseNullableDouble(_latCtrl.text) : _lat;
    final lng = _useMapCoords ? _parseNullableDouble(_lngCtrl.text) : _lng;
    final areaStoredM2 = _areaValueInSquareMeters() ?? _parseDouble(_area.text);
    final details = <String, dynamic>{
      'owner_id': ownerId,
      'title': _title.text.trim(),
      'description': _desc.text.trim(),
      'region': _region.text.trim(),
      'governorate': _governorate.text.trim(),
      'city': _city.text.trim(),
      'location': _location.text.trim(),
      'address_line': _addressLine.text.trim(),
      'type': _type,
      'purpose': _purpose,
      'area': areaStoredM2,
      'price': _parseDouble(_price.text),
      'price_includes_vat': _priceIncludesVat ?? true,
      'vat_rate': _kVatRate,
      'marketing_commission_kind': _commissionKind,
      'marketing_commission_rate': _kMarketingCommissionRate,
      'marketing_commission_amount':
          _commissionKind == 'fixed' ? _fixedCommissionValue() : 0,
      'currency': _currency,
      'negotiable': _negotiable,
      'price_on_sum': _priceOnSum,
      'accepts_mortgage_finance': _acceptsMortgageFinance,
      'no_legal_obstacles': _noLegalObstacles,
      'advertiser_role': _advertiserRole,
      'location_is_approximate': _locationIsApproximate,
      'property_age_bucket': _propertyAgeBucket,
      'is_auction': _isAuction,
      'current_bid': _isAuction ? _parseDouble(_currentBid.text) : null,
      'latitude': lat,
      'longitude': lng,
      'video_url': _videoUrl.text.trim().isEmpty ? null : _videoUrl.text.trim(),
      'listing_guidance': _listingGuidanceForInsert(),
      'virtual_tour_url': _virtualTourUrl.text.trim().isEmpty
          ? null
          : _virtualTourUrl.text.trim(),
      'availability_date': _availabilityDate == null
          ? null
          : DateTime(_availabilityDate!.year, _availabilityDate!.month,
                  _availabilityDate!.day)
              .toIso8601String()
              .substring(0, 10),
      'amenities': _amenitiesPayloadOrNull(),
      'extra_details': _buildExtraDetails(),
      'show_advertiser_name': _showOwnerNameOnCards,
      'owner_requests_public_name': _showOwnerNameOnCards,
      'publisher_public_name_source': _pubNameSource.name,
      'publisher_public_phone_source': _pubPhoneSource.name,
      'publisher_publish_presence': _publishPresenceOnCards,
      if (_showOwnerNameOnCards)
        'advertiser_public_name':
            PublisherIdentityPrefs.instance.resolvedPublicName(isAr: _isAr),
      if (_pubPhoneSource != PublicPhoneSource.hidden)
        'contact_phone':
            PublisherIdentityPrefs.instance.resolvedPublicPhone(),
    };
    final dNorm = normalizeDeedNumber(_deedNumber.text);
    details['deed_number'] = dNorm.isEmpty ? null : dNorm;
    details['deed_date'] = _deedDate == null
        ? null
        : DateTime(_deedDate!.year, _deedDate!.month, _deedDate!.day)
            .toIso8601String()
            .substring(0, 10);
    details['deed_issuer'] =
        _deedIssuer.text.trim().isEmpty ? null : _deedIssuer.text.trim();
    final bNum = _buildingNumber.text.trim();
    details['building_number'] =
        (_showBuildingNumber && bNum.isNotEmpty) ? bNum : null;
    if (_isLand) {
      details['facade'] = _facade;
      details['street_count'] = _streetCount;
      details['street_widths'] = _buildStreetWidths();
      details['land_use'] = _landUse;
      details['is_corner'] = _isCornerLand;
      details['plan_number'] = _planNumber.text.trim();
      details['parcel_number'] = _parcelNumber.text.trim();
    }
    if (_isProject) {
      details['area'] = _plotArea ?? _parseDouble(_area.text);
    }
    if (_roomStatsForSave) {
      details['bedrooms'] = _bedrooms;
      details['bathrooms'] = _bathrooms;
    } else {
      details['bedrooms'] = null;
      details['bathrooms'] = null;
    }
    if (_showParkingYearRow) {
      details['parking_spots'] = _parkingSpots;
      details['year_built'] = _yearBuilt;
    } else {
      details['parking_spots'] = null;
      details['year_built'] = null;
    }
    if (_showFurnishedRow) {
      details['furnished'] = _furnished;
    } else {
      details['furnished'] = null;
    }
    details['floor'] = _showFloorFields ? _floor : null;
    details['total_floors'] = _showFloorFields ? _totalFloors : null;
    if (widget.marketingFlow?.listingRequestOnly == true) {
      details['no_rega_ad_license'] = true;
      details['market_without_rega_license'] = true;
      details['market_consent'] = true;
      if (widget.marketingFlow?.showOwnerPhoneOnMarket == true) {
        details['show_owner_phone_on_market'] = true;
        details['reveal_phone_from_market'] = true;
      }
    }
    if (_regaPayloadForInsert.isNotEmpty) {
      details['rega_payload'] = _regaPayloadForInsert;
    }
    return <String, dynamic>{
      'owner_id': ownerId,
      'title': _title.text.trim(),
      'description': _desc.text.trim(),
      'city': _city.text.trim(),
      'price': _parseDouble(_price.text),
      'price_includes_vat': _priceIncludesVat ?? true,
      'vat_rate': _kVatRate,
      'marketing_commission_kind': _commissionKind,
      'marketing_commission_rate': _kMarketingCommissionRate,
      'marketing_commission_amount':
          _commissionKind == 'fixed' ? _fixedCommissionValue() : 0,
      'default_cover_used': _usedDefaultCover,
      'status': 'pending',
      'workflow_stage': 'waiting_marketers',
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      'payload_json': jsonEncode(details),
    };
  }

  Future<List<String>> _uploadRequestImages(
      {required String ownerId, required String requestId}) async {
    final bucket = _sb.storage.from('property-images');
    final uuid = const Uuid();
    final paths = <String>[];
    for (int i = 0; i < _images.length; i++) {
      final picked = _images[i];
      final fileName = '${uuid.v4()}.jpg';
      final path = 'requests/$requestId/$ownerId/$fileName';
      Uint8List bytesToUpload = picked.bytes;
      try {
        bytesToUpload = await WatermarkService.addTextWatermark(picked.bytes,
            text: AppBranding.copyrightBilingual());
      } catch (_) {
        bytesToUpload = picked.bytes;
      }
      await bucket.uploadBinary(path, bytesToUpload,
          fileOptions:
              const FileOptions(upsert: false, contentType: 'image/jpeg'));
      paths.add(path);
    }
    final patch = <String, dynamic>{'request_image_paths': paths};
    final vPath = _videoUrl.text.trim();
    if (vPath.isNotEmpty) {
      patch['request_video_path'] = vPath;
    }
    await _mergeRequestPayloadJson(requestId, patch);
    return paths;
  }

  /// يحفظ مسارات الصور داخل `payload_json` لأن أعمدة image_paths/images غير مضمونة في المخطط.
  Future<void> _mergeRequestPayloadJson(
    String requestId,
    Map<String, dynamic> patch,
  ) async {
    try {
      final row = await _sb
          .from('listing_requests')
          .select('payload_json')
          .eq('id', requestId)
          .maybeSingle();
      Map<String, dynamic> merged = {};
      final raw = row?['payload_json'];
      if (raw is String && raw.trim().isNotEmpty) {
        final dec = jsonDecode(raw);
        if (dec is Map) {
          merged = Map<String, dynamic>.from(dec);
        }
      } else if (raw is Map) {
        merged = Map<String, dynamic>.from(raw);
      }
      merged.addAll(patch);
      if (patch['request_image_paths'] is List &&
          (patch['request_image_paths'] as List).isNotEmpty) {
        merged['default_cover_used'] = false;
      }
      await _sb.from('listing_requests').update({
        'payload_json': jsonEncode(merged),
        if ((patch['request_image_paths'] as List?)?.isNotEmpty == true)
          'default_cover_used': false,
      }).eq('id', requestId);
    } catch (_) {}
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
    if (row['is_auction'] == true) {
      purp = 'auction';
    }
    return const {'sale', 'auction', 'investment'}.contains(purp);
  }

  Future<String?> _blockingDuplicateSaleDeedMessage() async {
    const salePurposes = {'sale', 'auction', 'investment'};
    if (!salePurposes.contains(_purpose)) return null;
    final deed = normalizeDeedNumber(_deedNumber.text);
    if (deed.isEmpty) return null;
    try {
      final res = await _sb
          .from('properties')
          .select('id,title,status,is_auction,deleted_by_user,delete_approved')
          .eq('deed_number', deed)
          .limit(40);
      final list = (res as List).cast<Map<String, dynamic>>();
      for (final row in list) {
        if (_rowStillListedForSaleLike(row)) {
          final t = (row['title'] ?? '').toString().trim();
          return _isAr
              ? 'يوجد إعلان آخر بنفس رقم الصك ما زال نشطًا للبيع أو المزاد أو الاستثمار${t.isNotEmpty ? ': $t' : ''}.'
              : 'Another listing with the same deed is still active for sale/auction/investment${t.isNotEmpty ? ': $t' : ''}.';
        }
      }
    } catch (_) {}
    return null;
  }

  /// يمنع إعادة نشر نفس المحتوى فوراً (خصائص + طلبات تسويق خلال 24 ساعة).
  String? _lastSuccessfulPublishFingerprint;

  String _currentPublishFingerprint() {
    return PublishContentFingerprintStore.build(
      title: _title.text,
      city: _city.text,
      price: _parseDouble(_price.text),
      area: _parseDouble(_area.text),
      deed: normalizeDeedNumber(_deedNumber.text),
      purpose: _purpose,
    );
  }

  Future<String?> _blockingRecentIdenticalContentMessage(String ownerId) async {
    final title = _title.text.trim();
    final city = _city.text.trim();
    if (title.isEmpty || city.isEmpty) return null;
    final price = _parseDouble(_price.text);
    final area = _parseDouble(_area.text);
    final deed = normalizeDeedNumber(_deedNumber.text);
    final fingerprint = _currentPublishFingerprint();
    final memHit = _lastSuccessfulPublishFingerprint == fingerprint;
    final stored = await PublishContentFingerprintStore.readIfFresh();
    if (memHit || stored == fingerprint) {
      return _isAr
          ? 'لقد نشرت للتو إعلاناً بنفس البيانات. راجع «صفحتي» أو غيّر البيانات قبل إعادة النشر.'
          : 'You just published an identical listing. Check My Page or change the data before publishing again.';
    }
    try {
      final since = DateTime.now()
          .toUtc()
          .subtract(PublishContentFingerprintStore.window)
          .toIso8601String();
      final res = await _sb
          .from('properties')
          .select(
            'id,title,city,price,area,deed_number,created_at,deleted_by_user',
          )
          .eq('owner_id', ownerId)
          .gte('created_at', since)
          .limit(40);
      final list = (res as List).cast<Map<String, dynamic>>();
      for (final row in list) {
        if (row['deleted_by_user'] == true) continue;
        if (_rowMatchesCurrentListingContent(
          row,
          title,
          city,
          price,
          area,
          deed,
        )) {
          return _isAr
              ? 'يبدو أنك نشرت إعلاناً مطابقاً خلال الـ 24 ساعة الماضية. راجع «صفحتي» قبل إعادة النشر.'
              : 'An identical listing was published in the last 24 hours. Check My Page before publishing again.';
        }
      }
    } catch (_) {}
    try {
      final since = DateTime.now()
          .toUtc()
          .subtract(PublishContentFingerprintStore.window)
          .toIso8601String();
      final res = await _sb
          .from('listing_requests')
          .select('id,title,city,price,area,created_at,status')
          .eq('owner_id', ownerId)
          .gte('created_at', since)
          .limit(40);
      final list = (res as List).cast<Map<String, dynamic>>();
      for (final row in list) {
        final st = (row['status'] ?? '').toString().toLowerCase();
        if (st.contains('cancel') ||
            st.contains('reject') ||
            st == 'deleted') {
          continue;
        }
        if (_rowMatchesCurrentListingContent(
          row,
          title,
          city,
          price,
          area,
          deed,
        )) {
          return _isAr
              ? 'طلب تسويق مطابق قُدِّم منذ قليل. راجع «صفحتي» قبل إعادة الإرسال.'
              : 'An identical marketing request was submitted recently. Check My Page before sending again.';
        }
      }
    } catch (_) {}
    return null;
  }

  bool _rowMatchesCurrentListingContent(
    Map<String, dynamic> row,
    String title,
    String city,
    double price,
    double area,
    String deed,
  ) {
    final sameTitle =
        (row['title'] ?? '').toString().trim().toLowerCase() ==
            title.toLowerCase();
    final sameCity =
        (row['city'] ?? '').toString().trim().toLowerCase() ==
            city.toLowerCase();
    final rowPrice = (row['price'] as num?)?.toDouble() ?? -1;
    final rowArea = (row['area'] as num?)?.toDouble() ?? -1;
    final samePrice = (rowPrice - price).abs() < 0.01;
    final sameArea = (rowArea - area).abs() < 0.01;
    if (!(sameTitle && sameCity && samePrice && sameArea)) return false;
    if (deed.isEmpty) return true;
    final rowDeed =
        normalizeDeedNumber((row['deed_number'] ?? '').toString());
    if (rowDeed.isEmpty) return true;
    return rowDeed == deed;
  }

  /// عند عدم رفع أي وسائط، نُعلّم الغلاف الذكي في قاعدة البيانات
  /// ([default_cover_used]) — يُعرض محلياً حسب المنصة (ويب/تطبيق) في كل الشاشات.
  bool _usedDefaultCover = false;

  void _markSmartDefaultCoverIfNoMedia() {
    if (_images.isNotEmpty || _videoUrl.text.trim().isNotEmpty) {
      _usedDefaultCover = false;
      return;
    }
    _usedDefaultCover = true;
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_termsAccepted) {
      setState(() => _error = _isAr
          ? 'يجب الموافقة على الشروط والأحكام قبل النشر.'
          : 'You must accept the terms before publishing.');
      return;
    }
    if (!_noLegalObstacles) {
      setState(() => _error = _isAr
          ? 'يجب تأكيد أن العقار خالٍ مما يمنع التصرف أو الانتفاع.'
          : 'Confirm there is nothing preventing disposal or use of the property.');
      return;
    }
    _maybeSuggestSmartTitle();
    final user = _sb.auth.currentUser;
    if (user == null) {
      setState(() =>
          _error = _isAr ? 'يجب تسجيل الدخول أولاً' : 'You must sign in first');
      return;
    }
    final ownerId = _resolveOwnerId();
    if (ownerId.isEmpty || ownerId != user.id) {
      setState(() => _error = _isAr ? 'غير مصرح' : 'Not allowed');
      return;
    }
    setState(() => _markSmartDefaultCoverIfNoMedia());
    if (!_usedDefaultCover &&
        _images.isEmpty &&
        _videoUrl.text.trim().isEmpty) {
      setState(() => _error = _isAr
          ? 'أضف صورة أو فيديو، أو سيُستخدم الغلاف الذكي تلقائياً.'
          : 'Add a photo or video, or the smart cover will be used.');
      _scrollToKey(_listingMediaKey);
      return;
    }
    if (!_usageResidential && !_usageCommercial) {
      setState(() => _error = _isAr
          ? 'حدد ما إذا كان العقار مناسبًا للسكني أو التجاري أو كليهما'
          : 'Select whether the property is suitable for residential and/or commercial use');
      _scrollToKey(_formCardKey);
      return;
    }
    await _tryAutoFillRegionAndCoordsFromCity();
    if (_useMapCoords) {
      final lat = _parseNullableDouble(_latCtrl.text);
      final lng = _parseNullableDouble(_lngCtrl.text);
      if (lat == null || lng == null) {
        setState(() => _error = _isAr
            ? 'الإحداثيات إلزامية عند تفعيل خيار الخريطة'
            : 'Coordinates are required when map option is enabled');
        _scrollToKey(_coordsKey);
        return;
      }
      _lat = lat;
      _lng = lng;
    }
    if (_isLand && _streetCount != null && _streetCount! > 0) {
      final widths = _buildStreetWidths();
      if (widths.length < _streetCount!) {
        setState(() => _error = _isAr
            ? 'يجب إدخال عرض الشارع لكل شارع'
            : 'Please enter street width for each street');
        _scrollToKey(_formCardKey);
        return;
      }
    }
    final formOk = (_formKeyClassification.currentState?.validate() ?? true) &&
        (_formKeyLocation.currentState?.validate() ?? true) &&
        (_formKeyPricing.currentState?.validate() ?? true) &&
        (_formKeyDetails.currentState?.validate() ?? true);
    if (!formOk) {
      _scrollToKey(_formCardKey);
      return;
    }
    if (_useMapCoords) {
      final coordsOk = _formKeyCoords.currentState?.validate() ?? false;
      if (!coordsOk) {
        _scrollToKey(_coordsKey);
        return;
      }
    }
    if (_requiresDeed) {
      if (normalizeDeedNumber(_deedNumber.text).isEmpty) {
        setState(() => _error = _isAr
            ? 'رقم الصك مطلوب لهذا الغرض'
            : 'Deed number is required for this purpose');
        _scrollToKey(_formCardKey);
        return;
      }
      if (_deedDate == null) {
        setState(() =>
            _error = _isAr ? 'تاريخ الصك مطلوب' : 'Deed date is required');
        _scrollToKey(_formCardKey);
        return;
      }
      if (_deedIssuer.text.trim().isEmpty) {
        setState(() => _error =
            _isAr ? 'الجهة المصدرة للصك مطلوبة' : 'Deed issuer is required');
        _scrollToKey(_formCardKey);
        return;
      }
    }
    if (_showParkingYearRow && _yearBuilt == null) {
      setState(() =>
          _error = _isAr ? 'سنة البناء مطلوبة' : 'Year built is required');
      _scrollToKey(_formCardKey);
      return;
    }
    _advertiserRole = _advertiserRoleCode;
    final dupMsg = await _blockingDuplicateSaleDeedMessage();
    if (dupMsg != null) {
      if (!mounted) return;
      setState(() => _error = dupMsg);
      _scrollToKey(_formCardKey);
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
    final identicalMsg = await _blockingRecentIdenticalContentMessage(ownerId);
    if (identicalMsg != null) {
      if (!mounted) return;
      setState(() => _error = identicalMsg);
      _scrollToKey(_formCardKey);
      return;
    }
    setState(() {
      _saving = true;
      _publishLock = true;
    });
    try {
      final verified = await _isVerifiedMarketer(ownerId);
      if (!verified || _forceListingRequestPath) {
        // فرد أو مسوّق بدون ترخيص REGA: طلب تسويق — لا يظهر في الرئيسية.
        final requestPayload = _buildRequestPayload(ownerId: ownerId);
        Map<String, dynamic> insertedReq;
        try {
          insertedReq = await _sb
              .from('listing_requests')
              .insert(requestPayload)
              .select('id,listing_request_public_code')
              .single();
        } catch (e) {
          final msg = e.toString().toLowerCase();
          // — تنظيف الأعمدة الجديدة إن لم يكن الترحيل V9 قد طُبِّق على هذه البيئة.
          var changed = false;
          for (final col in const [
            'price_includes_vat',
            'vat_rate',
            'marketing_commission_kind',
            'marketing_commission_rate',
            'marketing_commission_amount',
            'default_cover_used',
          ]) {
            if (msg.contains(col) && msg.contains('does not exist')) {
              requestPayload.remove(col);
              changed = true;
            }
          }
          if (changed) {
            insertedReq = await _sb
                .from('listing_requests')
                .insert(requestPayload)
                .select('id,listing_request_public_code')
                .single();
          } else if (msg.contains('listing_request_public_code') &&
              (msg.contains('column') ||
                  msg.contains('schema') ||
                  msg.contains('could not find'))) {
            insertedReq = await _sb
                .from('listing_requests')
                .insert(requestPayload)
                .select('id')
                .single();
          } else {
            rethrow;
          }
        }
        final requestId = insertedReq['id'] as String;
        final reqPub =
            (insertedReq['listing_request_public_code'] ?? '').toString().trim();
        OrgActivityService.logListingRequestCreated(requestId);
        try {
          await MarketingFlowService(_sb).notifyOwnerListingRequestSubmitted(
            ownerId: ownerId,
            requestId: requestId,
            titleHint: _title.text.trim(),
          );
        } catch (_) {}
        try {
          await _uploadRequestImages(ownerId: ownerId, requestId: requestId);
        } catch (_) {}
    if (!mounted) return;
    // احفظ بصمة المحتوى فوراً بعد النجاح (قبل الحوار) لمنع إعادة النشر المطابق.
    final fp = _currentPublishFingerprint();
    _lastSuccessfulPublishFingerprint = fp;
    unawaited(PublishContentFingerprintStore.save(fp));
    await _showRequestSuccess(
      requestId: requestId,
      listingRequestPublicCode: reqPub.isEmpty ? null : reqPub,
    );
    return;
      }
      if (widget.marketingFlow?.publishToHomeFeed == true &&
          !_licensedAdPayloadComplete()) {
        if (!mounted) return;
        setState(() {
          _error = _isAr
              ? 'لا يمكن النشر في الرئيسية دون ترخيص إعلان REGA مكتمل والتحقق منه.'
              : 'Home publish requires a complete verified REGA ad license.';
          _saving = false;
          _publishLock = false;
        });
        return;
      }
      final marketerDirectPublish = _forceListingRequestPath
          ? false
          : (widget.marketingFlow?.publishToHomeFeed == true
              ? _licensedAdPayloadComplete()
              : _regaVerificationSatisfied());
      bool hasLocationColumn = true;
      Map<String, dynamic> payload = _buildPayload(
        ownerId: ownerId,
        hasLocationColumn: hasLocationColumn,
        marketerDirectPublish: marketerDirectPublish,
      );
      Map<String, dynamic> inserted;
      try {
        inserted =
            await _sb
                .from('properties')
                .insert(payload)
                .select('id,listing_public_code')
                .single();
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('contact_phone') && msg.contains('does not exist')) {
          payload.remove('contact_phone');
        }
        for (final col in [
          'workflow_stage',
          'purpose',
          'waiting_marketers_since',
          'extra_details',
          'facade',
          'street_count',
          'street_widths',
          'deed_number',
          'deed_date',
          'deed_issuer',
          'building_number',
          'listing_guidance',
          'rega_payload',
          'published_at',
          'published_by_marketer_id',
          'price_includes_vat',
          'vat_rate',
          'marketing_commission_kind',
          'marketing_commission_rate',
          'marketing_commission_amount',
          'default_cover_used',
          'publisher_public_name_source',
          'publisher_public_phone_source',
          'publisher_publish_presence',
          'advertiser_public_name',
          'contact_phone',
        ]) {
          if (msg.contains(col) && msg.contains('does not exist')) {
            payload.remove(col);
          }
        }
        if (msg.contains('location') && msg.contains('does not exist')) {
          hasLocationColumn = false;
          payload = _buildPayload(
            ownerId: ownerId,
            hasLocationColumn: hasLocationColumn,
            marketerDirectPublish: marketerDirectPublish,
          );
          if (msg.contains('contact_phone') && msg.contains('does not exist')) {
            payload.remove('contact_phone');
          }
        }
        inserted =
            await _sb
                .from('properties')
                .insert(payload)
                .select('id,listing_public_code')
                .single();
      }
      final propertyId = inserted['id'] as String;
      OrgActivityService.logListingCreated(propertyId);
      try {
        await MarketingFlowService(_sb).notifyOwnerPropertyListed(
          ownerId: ownerId,
          propertyId: propertyId,
          titleHint: _title.text.trim(),
        );
      } catch (_) {}
      final bucket = _sb.storage.from('property-images');
      final uuid = const Uuid();
      final imagesToInsert = <Map<String, dynamic>>[];
      for (int i = 0; i < _images.length; i++) {
        final picked = _images[i];
        final fileName = '${uuid.v4()}.jpg';
        final path = '$ownerId/$fileName';
        Uint8List bytesToUpload = picked.bytes;
        try {
          bytesToUpload = await WatermarkService.addTextWatermark(picked.bytes,
              text: AppBranding.copyrightBilingual());
        } catch (_) {
          bytesToUpload = picked.bytes;
        }
        await bucket.uploadBinary(path, bytesToUpload,
            fileOptions:
                const FileOptions(upsert: false, contentType: 'image/jpeg'));
        imagesToInsert
            .add({'property_id': propertyId, 'path': path, 'sort_order': i});
      }
      if (imagesToInsert.isNotEmpty) {
        await _sb.from('property_images').insert(imagesToInsert);
      }
      final videoPath = _videoUrl.text.trim();
      if (videoPath.isNotEmpty) {
        try {
          await _sb.from('property_images').insert({
            'property_id': propertyId,
            'path': videoPath,
            'file_name': videoPath,
            'media_type': 'video',
            'sort_order': imagesToInsert.length,
          });
        } catch (_) {
          // مخطط قديم بدون media_type أو سياسة RLS مختلفة — يبقى video_url على صف العقار.
        }
      }
    if (!mounted) return;
    // احفظ بصمة المحتوى فوراً بعد النجاح (قبل الحوار) لمنع إعادة النشر المطابق.
    final fp = _currentPublishFingerprint();
    _lastSuccessfulPublishFingerprint = fp;
    unawaited(PublishContentFingerprintStore.save(fp));
    final pub = (inserted['listing_public_code'] ?? '').toString().trim();
    await _showSuccessChoice(
      listingPublicCode: pub.isEmpty ? null : pub,
    );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _publishLock = false;
      });
    } finally {
      // — `_saving` يُعاد لـ `false` فوراً ليرفع شاشة الحفظ، أمّا `_publishLock`
      //   فيُعاد فقط عند الفشل أو بعد إغلاق حوار النجاح (داخل _showSuccessChoice /
      //   _showRequestSuccess) لمنع نشر الإعلان مرتين عبر الضغط المتكرر.
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvailabilityDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _availabilityDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
      helpText:
          _isAr ? 'تاريخ التوفر (اختياري)' : 'Availability date (optional)',
      cancelText: _isAr ? 'إلغاء' : 'Cancel',
      confirmText: _isAr ? 'اختيار' : 'Select',
    );
    if (!mounted) return;
    if (picked == null) return;
    setState(() => _availabilityDate = picked);
  }

  Future<void> _pickDeedDate() async {
    final picked = await showDeedDateCalendarDialog(
      context: context,
      isAr: _isAr,
      initialDate: _deedDate,
    );
    if (!mounted) return;
    if (picked == null) return;
    setState(() => _deedDate = picked);
  }

  Future<void> _pickAndUploadLicensePdf() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    setState(() => _uploadingLicensePdf = true);
    suspendAutoLock.value = true;
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (!mounted) return;
      if (res == null || res.files.isEmpty) {
        setState(() => _uploadingLicensePdf = false);
        suspendAutoLock.value = false;
        return;
      }
      final f = res.files.single;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        setState(() => _uploadingLicensePdf = false);
        suspendAutoLock.value = false;
        return;
      }
      final uuid = const Uuid().v4();
      final path = 'licenses/${user.id.trim()}/$uuid.pdf';
      await _sb.storage.from('property-images').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: false,
              contentType: 'application/pdf',
            ),
          );
      if (!mounted) return;
      setState(() {
        _licensePdfStoragePath = path;
        _uploadingLicensePdf = false;
      });
      suspendAutoLock.value = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(_isAr ? 'تم رفع ملف الرخصة' : 'License PDF uploaded'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingLicensePdf = false);
      suspendAutoLock.value = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(_isAr ? 'تعذر رفع PDF' : 'PDF upload failed'),
        ),
      );
    }
  }

  void _clearLicensePdf() {
    setState(() => _licensePdfStoragePath = null);
  }

  Future<void> _showExtendedUsesDialog() async {
    final ctrl = TextEditingController(text: _extendedUsageNotes.text);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            _isAr ? 'استخدامات موسّعة وتفاصيل إضافية' : 'Extended uses & notes',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          content: SingleChildScrollView(
            child: AqarTextField(
              controller: ctrl,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: _isAr
                    ? 'مثال: واجهتان تجاريتان، أهلية سكنية، إلخ.'
                    : 'e.g. dual commercial frontage, residential eligibility…',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_isAr ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                setState(() => _extendedUsageNotes.text = ctrl.text);
                Navigator.pop(ctx);
              },
              child: Text(_isAr ? 'حفظ' : 'Save'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
  }

  void _clearLandOnlyFormFields() {
    _landUse = null;
    _facade = null;
    _streetCount = null;
    _streetWidth1.clear();
    _streetWidth2.clear();
    _streetWidth3.clear();
    _streetWidth4.clear();
    _isCornerLand = false;
    _planNumber.clear();
    _parcelNumber.clear();
    _boundaryNorth.clear();
    _boundarySouth.clear();
    _boundaryEast.clear();
    _boundaryWest.clear();
  }

  String _guessVideoMime(String ext) {
    switch (ext.toLowerCase()) {
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

  Future<void> _uploadVideoBytes(Uint8List bytes, String ext) async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    setState(() => _uploadingVideo = true);
    suspendAutoLock.value = true;
    try {
      final uuid = const Uuid().v4();
      final path = '${user.id.trim()}/$uuid.${ext.toLowerCase()}';
      await _sb.storage.from('property-videos').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _guessVideoMime(ext),
            ),
          );
      if (!mounted) return;
      setState(() => _videoUrl.text = path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(_isAr ? 'تم رفع الفيديو' : 'Video uploaded'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(_isAr ? 'فشل رفع الفيديو: $e' : 'Upload failed: $e'),
        ),
      );
    } finally {
      suspendAutoLock.value = false;
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<void> _pickVideoFromFiles() async {
    if (_saving || _picking || _uploadingVideo) return;
    setState(() => _picking = true);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(_isAr ? 'تعذر قراءة الملف' : 'Could not read file'),
          ),
        );
        return;
      }
      final path = f.path;
      if (!await _videoPassesUploadPolicy(
        path: (path != null && path.isNotEmpty) ? path : null,
        bytes: bytes,
      )) {
        return;
      }
      final ext = (f.extension ?? 'mp4').toLowerCase();
      await _uploadVideoBytes(bytes, ext);
    } finally {
      suspendAutoLock.value = false;
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickVideoFromGallery() async {
    if (_saving || _picking || _uploadingVideo) return;
    final t = AppLocalizations.of(context);
    if (t != null &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      final ok = await RuntimePermissionHelper.ensurePhotos(context, t: t);
      if (!ok || !mounted) return;
    }
    setState(() => _picking = true);
    suspendAutoLock.value = true;
    try {
      final picker = ImagePicker();
      final x = await picker.pickVideo(source: ImageSource.gallery);
      if (!mounted || x == null) return;
      final path = x.path;
      final bytes = await x.readAsBytes();
      if (!await _videoPassesUploadPolicy(
        path: path.isNotEmpty ? path : null,
        bytes: bytes,
      )) {
        return;
      }
      final name = x.name.toLowerCase();
      final ext = name.contains('.') ? name.split('.').last : 'mp4';
      await _uploadVideoBytes(bytes, ext);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(_isAr ? 'تعذر اختيار الفيديو' : 'Could not pick video'),
        ),
      );
    } finally {
      suspendAutoLock.value = false;
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickVideoFromCamera() async {
    if (_saving || _picking || _uploadingVideo) return;
    final t = AppLocalizations.of(context);
    if (t != null &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      final ok = await RuntimePermissionHelper.ensureCamera(context, t: t);
      if (!ok || !mounted) return;
    }
    setState(() => _picking = true);
    suspendAutoLock.value = true;
    try {
      final picker = ImagePicker();
      final x = await picker.pickVideo(source: ImageSource.camera);
      if (!mounted || x == null) return;
      final path = x.path;
      final bytes = await x.readAsBytes();
      if (!await _videoPassesUploadPolicy(
        path: path.isNotEmpty ? path : null,
        bytes: bytes,
      )) {
        return;
      }
      final name = x.name.toLowerCase();
      final ext = name.contains('.') ? name.split('.').last : 'mp4';
      await _uploadVideoBytes(bytes, ext);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content:
              Text(_isAr ? 'تعذر التقاط الفيديو' : 'Could not record video'),
        ),
      );
    } finally {
      suspendAutoLock.value = false;
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _showVideoPickMenu() async {
    if (_saving || _uploadingVideo) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.video_file_outlined),
                title: Text(_isAr ? 'ملف فيديو' : 'Video file'),
                onTap: () => Navigator.pop(ctx, 'file'),
              ),
              ListTile(
                leading: const Icon(Icons.video_library_outlined),
                title: Text(_isAr ? 'معرض الوسائط' : 'Gallery'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              if (!kIsWeb)
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: Text(_isAr ? 'الكاميرا' : 'Camera'),
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
            ],
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'file':
        await _pickVideoFromFiles();
        break;
      case 'gallery':
        await _pickVideoFromGallery();
        break;
      case 'camera':
        await _pickVideoFromCamera();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pane = _wizardPaneKind(_wizardStep);
    final stepCount =
        _kWizardLastStep - (_marketingFlowActive ? 1 : 0) + 1;
    final displayStep =
        _marketingFlowActive ? _wizardStep : _wizardStep + 1;
    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: PopScope(
        canPop: _publishSucceeded ||
            (!_publishLock && !_saving && !_hasUnsavedWizardInput()),
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop || !mounted) return;
          if (_publishSucceeded) {
            Navigator.of(context).pop(true);
            return;
          }
          if (_publishLock || _saving) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(_isAr
                    ? 'جاري نشر الإعلان… يرجى الانتظار حتى ظهور رقم الإعلان.'
                    : 'Publishing in progress… please wait for the listing number.'),
              ),
            );
            return;
          }
          await _handleListingFormExit();
        },
        child: Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: (!widget.embedAppBar && !_publishLock && !_saving)
                ? AppPageCloseButton(
                    isArabic: _isAr,
                    onPressed: () {
                      if (Navigator.canPop(context)) Navigator.pop(context);
                    },
                  )
                : null,
            title: Text(_isAr ? 'إضافة إعلان' : 'Add Listing'),
          actions: [
            IconButton(
              tooltip: _isAr ? 'حفظ المسودة' : 'Save draft',
              onPressed: (_saving || _publishLock)
                  ? null
                  : () => unawaited(_persistListingDraft()),
              icon: const Icon(Icons.save_outlined),
            ),
            if (pane == 6)
              IconButton(
                tooltip: _isAr ? 'إضافة صور أو فيديو' : 'Add images or video',
                icon: (_picking || _uploadingVideo)
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: AppLogoLoading(compact: true, size: 22),
                      )
                    : const Icon(Icons.perm_media_outlined),
                onPressed: (_saving || _picking || _uploadingVideo)
                    ? null
                    : _showPickMediaMenu,
              ),
          ],
        ),
        body: Stack(
          children: [
            SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                _HeaderCard(
                  isAr: _isAr,
                  marketerPublishName: _marketerPublishName,
                ),
                const SizedBox(height: 12),
                Text(
                  _isAr
                      ? 'الخطوة $displayStep من $stepCount · ${_wizardScreenTitle(_isAr)}'
                      : 'Step $displayStep of $stepCount · ${_wizardScreenTitle(_isAr)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: displayStep / stepCount,
                  ),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _formCardKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Visibility(
                        visible: pane == 0 && !_marketingFlowActive,
                        maintainState: true,
                        child: KeyedSubtree(
                          key: _regaCardKey,
                          child: _AdLicenseStepCard(
                            isAr: _isAr,
                            adLicenseSource: _adLicenseSource,
                            onAdLicenseSourceChanged: (v) => setState(() {
                              _adLicenseSource = v;
                              if (v != _AdLicenseSource.external) {
                                _licensePdfStoragePath = null;
                              }
                            }),
                            propertyHasObligations: _propertyHasObligations,
                            onPropertyHasObligationsChanged: (v) =>
                                setState(() => _propertyHasObligations = v),
                            obligationsDetail: _obligationsDetail,
                            onOpenExtendedUses: _showExtendedUsesDialog,
                            extendedUsagePreview: _extendedUsageNotes.text,
                            regaFalLicenseNo: _regaFalLicenseNo,
                            regaChecking: _regaChecking,
                            regaVerifyBanner: _regaVerifyBanner,
                            regaVerifyOk: _regaVerifyOk,
                            onOpenRegaImport: _openRegaImportPage,
                          ),
                        ),
                      ),
                      Visibility(
                        visible:
                            pane == 1 || pane == 101 || pane == 102,
                        maintainState: true,
                        child: _buildPropertyFormSlice(
                          AddPropertyFormSlice.classification,
                          _formKeyClassification,
                        ),
                      ),
                      Visibility(
                        visible: pane == 2,
                        maintainState: true,
                        child: KeyedSubtree(
                          key: _coordsKey,
                          child: _CoordsCard(
                            isAr: _isAr,
                            saving: _saving,
                            enabled: _useMapCoords,
                            locationIsApproximate: _locationIsApproximate,
                            latController: _latCtrl,
                            lngController: _lngCtrl,
                            lat: _lat,
                            lng: _lng,
                            formKey: _formKeyCoords,
                            onToggle: (v) {
                              if (!v) {
                                setState(() {
                                  _useMapCoords = false;
                                  _lat = null;
                                  _lng = null;
                                  _latCtrl.clear();
                                  _lngCtrl.clear();
                                });
                                return;
                              }
                              setState(() {
                                _useMapCoords = true;
                                _lat = null;
                                _lng = null;
                                _latCtrl.clear();
                                _lngCtrl.clear();
                                _error = null;
                              });
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  _openMapPicker(kingdomOverview: true);
                                }
                              });
                            },
                            onPick: () => _openMapPicker(
                              kingdomOverview:
                                  _lat == null && _lng == null && _useMapCoords,
                            ),
                            onLatChanged: _onLatChanged,
                            onLngChanged: _onLngChanged,
                          ),
                        ),
                      ),
                      Visibility(
                        visible: pane == 3,
                        maintainState: true,
                        child: _buildPropertyFormSlice(
                          AddPropertyFormSlice.location,
                          _formKeyLocation,
                        ),
                      ),
                      Visibility(
                        visible: pane == 4,
                        maintainState: true,
                        child: _buildPropertyFormSlice(
                          AddPropertyFormSlice.pricing,
                          _formKeyPricing,
                        ),
                      ),
                      Visibility(
                        visible: pane == 5,
                        maintainState: true,
                        child: _buildPropertyFormSlice(
                          AddPropertyFormSlice.details,
                          _formKeyDetails,
                        ),
                      ),
                      Visibility(
                        visible: pane == 6,
                        maintainState: true,
                        child: KeyedSubtree(
                          key: _listingMediaKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_requiresExternalLicenseBundle) ...[
                                _ExternalLicenseMediaBanner(isAr: _isAr),
                                const SizedBox(height: 12),
                              ],
                              _ListingMediaCard(
                                isAr: _isAr,
                                images: _images,
                                saving: _saving,
                                picking: _picking,
                                uploadingVideo: _uploadingVideo,
                                hasVideo: _hasUploadedVideo,
                                showCoverHeroPicker: _images.isNotEmpty &&
                                    _videoUrl.text.trim().isNotEmpty,
                                coverHeroIsVideo: _coverHeroIsVideo,
                                onCoverHeroIsVideoChanged: (v) =>
                                    setState(() => _coverHeroIsVideo = v),
                                onPickImages: _showPickImagesMenu,
                                onPickVideo: _showVideoPickMenu,
                                onClearVideo: _clearUploadedVideo,
                                onRemoveImage: _removeImageAt,
                                onMoveImage: _moveImage,
                              ),
                              if (_requiresExternalLicenseBundle) ...[
                                const SizedBox(height: 14),
                                _LicensePdfUploadRow(
                                  isAr: _isAr,
                                  storagePath: _licensePdfStoragePath,
                                  uploading: _uploadingLicensePdf,
                                  busy: _saving ||
                                      _picking ||
                                      _uploadingVideo ||
                                      _uploadingLicensePdf,
                                  onPick: _pickAndUploadLicensePdf,
                                  onClear: _clearLicensePdf,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_error != null) _ErrorBox(text: _error!, isAr: _isAr),
                if (_wizardStep >= _kWizardLastStep) ...[
                  const SizedBox(height: 12),
                  _DealPublishExtrasCard(
                    isAr: _isAr,
                    saving: _saving || _publishLock,
                    noLegalObstacles: _noLegalObstacles,
                    onNoLegalObstaclesChanged: (v) =>
                        setState(() => _noLegalObstacles = v),
                    advertiserRoleLabel: _advertiserRoleLabel,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _isAr
                          ? 'إظهار اسمي/صفتي مع رمز التوثيق على بطاقات الرئيسية'
                          : 'Show my name/role with verification on Home cards',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    subtitle: Text(
                      _isAr
                          ? 'يمكن إخفاؤه لاحقاً؛ يظهر للزوار عند التفعيل فقط.'
                          : 'Visitors see it only when enabled.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    value: _showOwnerNameOnCards,
                    onChanged: (_saving || _publishLock)
                        ? null
                        : (v) => setState(() => _showOwnerNameOnCards = v),
                  ),
                  if (_showOwnerNameOnCards) ...[
                    const SizedBox(height: 8),
                    PublisherIdentityOptionsCard(
                      isAr: _isAr,
                      compact: true,
                      enabled: !(_saving || _publishLock),
                      nameSource: _pubNameSource,
                      phoneSource: _pubPhoneSource,
                      publishPresence: _publishPresenceOnCards,
                      officialName: _officialNameCached,
                      displayAlias: _displayAliasCached,
                      primaryPhone: _primaryPhoneCached,
                      secondaryPhone: _secondaryPhoneCached,
                      onNameSourceChanged: (v) async {
                        await PublisherIdentityPrefs.instance.setNameSource(v);
                        if (!mounted) return;
                        setState(() => _pubNameSource = v);
                      },
                      onPhoneSourceChanged: (v) async {
                        await PublisherIdentityPrefs.instance.setPhoneSource(v);
                        if (!mounted) return;
                        setState(() => _pubPhoneSource = v);
                      },
                      onPublishPresenceChanged: (v) async {
                        await PublisherIdentityPrefs.instance
                            .setPublishPresenceOnCards(v);
                        if (!mounted) return;
                        setState(() => _publishPresenceOnCards = v);
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  TermsAcceptanceCheckbox(
                    isAr: _isAr,
                    value: _termsAccepted,
                    onChanged: (_saving || _publishLock)
                        ? null
                        : (v) => setState(() => _termsAccepted = v == true),
                    onOpenTerms: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              PlatformPoliciesScreen(isAr: _isAr),
                        ),
                      );
                    },
                  ),
                ],
                if (kIsWeb && pane == 6) ...[
                  const SizedBox(height: 12),
                  Text(
                    _isAr
                        ? 'على الويب: اختر الملفات من جهازك للرفع.'
                        : 'On web: pick files from your device to upload.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 8),
                    ],
                      ),
                    ),
                  ),
                ),
              ),
              Material(
                elevation: 8,
                color: cs.surface,
                shadowColor: Colors.black26,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final narrow = c.maxWidth < 520;
                      final nextBtn = _wizardStep < _kWizardLastStep
                          ? FilledButton(
                              onPressed: (_saving ||
                                      _publishLock ||
                                      _picking ||
                                      _uploadingVideo ||
                                      _uploadingLicensePdf)
                                  ? null
                                  : _wizardNext,
                              child: Text(_isAr ? 'التالي' : 'Next'),
                            )
                          : FilledButton(
                              onPressed: (_saving ||
                                      _publishLock ||
                                      _picking ||
                                      _uploadingVideo ||
                                      _uploadingLicensePdf ||
                                      !_canSubmit)
                                  ? null
                                  : _submit,
                              child: (_saving || _publishLock)
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: AppLogoLoading(
                                              compact: true, size: 20),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            _isAr
                                                ? 'جاري مراجعة التفاصيل والنشر…'
                                                : 'Reviewing details & publishing…',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      _isAr
                                          ? 'نشر الإعلان'
                                          : 'Publish listing'),
                            );
                      final backBtn = OutlinedButton(
                        onPressed: (_wizardStep >
                                    (_marketingFlowActive ? 1 : 0) &&
                                !_saving)
                            ? _wizardPrev
                            : null,
                        child: Text(_isAr ? 'السابق' : 'Back'),
                      );
                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            nextBtn,
                            const SizedBox(height: 8),
                            backBtn,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: backBtn),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: nextBtn),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
            if (_saving)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Center(
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(16),
                      color: cs.surface,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const AppLogoLoading(compact: true, size: 44),
                            const SizedBox(height: 14),
                            Text(
                              _isAr
                                  ? 'جاري مراجعة التفاصيل والنشر'
                                  : 'Reviewing details & publishing',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
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
      ),
    );
  }
}

// =======================
// Widgets الفرعية
// =======================

class _AdLicenseStepCard extends StatelessWidget {
  final bool isAr;
  final _AdLicenseSource adLicenseSource;
  final ValueChanged<_AdLicenseSource> onAdLicenseSourceChanged;
  final bool? propertyHasObligations;
  final ValueChanged<bool?> onPropertyHasObligationsChanged;
  final TextEditingController obligationsDetail;
  final VoidCallback onOpenExtendedUses;
  final String extendedUsagePreview;
  final TextEditingController regaFalLicenseNo;
  final bool regaChecking;
  final String? regaVerifyBanner;
  final bool? regaVerifyOk;
  final VoidCallback onOpenRegaImport;

  const _AdLicenseStepCard({
    required this.isAr,
    required this.adLicenseSource,
    required this.onAdLicenseSourceChanged,
    required this.propertyHasObligations,
    required this.onPropertyHasObligationsChanged,
    required this.obligationsDetail,
    required this.onOpenExtendedUses,
    required this.extendedUsagePreview,
    required this.regaFalLicenseNo,
    required this.regaChecking,
    required this.regaVerifyBanner,
    required this.regaVerifyOk,
    required this.onOpenRegaImport,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF0F766E).withOpacity(0.14),
                cs.surface,
              ],
              begin: AlignmentDirectional.topEnd,
              end: AlignmentDirectional.bottomStart,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF0F766E).withOpacity(0.38),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.account_balance_outlined,
                    color: Color(0xFF0F766E),
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isAr
                          ? 'الهيئة العامة للعقار ورخصة الإعلان'
                          : 'REGA & advertisement license',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isAr
                    ? 'المالك الفرد يستطيع المتابعة بدون رخصة فال. المسوق المرخّص يربط رخصة فال وترخيص الإعلان من الهيئة عند وجود إعلان جاهز.'
                    : 'Individual owners can continue without FAL. Licensed marketers link FAL and the REGA ad license when a licensed ad is ready.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          isAr ? 'مصدر رخصة الإعلان' : 'Ad license source',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StableSelectChip(
              label: isAr ? 'من داخل التطبيق' : 'In-app',
              exclusive: true,
              selected: adLicenseSource == _AdLicenseSource.inApp,
              onSelected: (_) =>
                  onAdLicenseSourceChanged(_AdLicenseSource.inApp),
            ),
            StableSelectChip(
              label: isAr ? 'من خارج التطبيق' : 'Outside app',
              exclusive: true,
              selected: adLicenseSource == _AdLicenseSource.external,
              onSelected: (_) =>
                  onAdLicenseSourceChanged(_AdLicenseSource.external),
            ),
            StableSelectChip(
              label: isAr ? 'لا يوجد بعد' : 'None yet',
              exclusive: true,
              selected: adLicenseSource == _AdLicenseSource.none,
              onSelected: (_) =>
                  onAdLicenseSourceChanged(_AdLicenseSource.none),
            ),
          ],
        ),
        if (adLicenseSource != _AdLicenseSource.none) ...[
          const SizedBox(height: 14),
          Text(
            isAr
                ? 'رقم رخصة فال / الوساطة (10 أرقام)'
                : 'FAL / brokerage license (10 digits)',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 6),
          AqarTextFormField(
            controller: regaFalLicenseNo,
            keyboardType: TextInputType.number,
            inputFormatters: latinDigitsOnlyFormatters(maxLength: 10),
            maxLength: 10,
            decoration: InputDecoration(
              counterText: '',
              labelText:
                  isAr ? 'رقم الرخصة (10 أرقام)' : 'License number (10 digits)',
              hintText:
                  isAr ? 'أدخل 10 أرقام أو الصقها' : 'Type or paste 10 digits',
            ),
          ),
          if (regaChecking) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (regaVerifyBanner != null &&
              regaVerifyBanner!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              regaVerifyBanner!,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: regaVerifyOk == true
                    ? const Color(0xFF0F766E)
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onOpenRegaImport,
            icon: const Icon(Icons.link, size: 20),
            label: Text(
              isAr ? 'ربط عبر صفحة الهيئة (ElanDetails)' : 'Link via REGA page',
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          isAr ? 'التزامات على العقار (إلزامي)' : 'Property obligations *',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StableSelectChip(
              label: isAr ? 'نعم' : 'Yes',
              exclusive: true,
              selected: propertyHasObligations == true,
              onSelected: (_) => onPropertyHasObligationsChanged(true),
            ),
            StableSelectChip(
              label: isAr ? 'لا' : 'No',
              exclusive: true,
              selected: propertyHasObligations == false,
              onSelected: (_) => onPropertyHasObligationsChanged(false),
            ),
          ],
        ),
        if (propertyHasObligations == true) ...[
          const SizedBox(height: 10),
          AqarTextFormField(
            controller: obligationsDetail,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: isAr
                  ? 'وصف موجز للالتزامات *'
                  : 'Brief description of obligations *',
            ),
          ),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onOpenExtendedUses,
          icon: const Icon(Icons.open_in_new, size: 20),
          label: Text(
            isAr
                ? 'استخدامات موسّعة وتفاصيل إضافية'
                : 'Extended uses & extra detail',
          ),
        ),
        if (extendedUsagePreview.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            isAr
                ? 'تم حفظ ملاحظات إضافية (${extendedUsagePreview.length} حرفاً)'
                : 'Saved extended notes (${extendedUsagePreview.length} chars)',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _ExternalLicenseMediaBanner extends StatelessWidget {
  final bool isAr;

  const _ExternalLicenseMediaBanner({required this.isAr});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: cs.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isAr
                  ? 'رخصة خارج التطبيق: يجب إرفاق صور للعقار، وفيديو، وملف PDF للرخصة.'
                  : 'External license: you must attach photos, a video, and a PDF of the license.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LicensePdfUploadRow extends StatelessWidget {
  final bool isAr;
  final String? storagePath;
  final bool uploading;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _LicensePdfUploadRow({
    required this.isAr,
    required this.storagePath,
    required this.uploading,
    required this.busy,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final has = (storagePath ?? '').trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: FieldGroupTheme.boxDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isAr ? 'ملف PDF لرخصة الإعلان *' : 'Ad license PDF *',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (has)
            Row(
              children: [
                Icon(Icons.picture_as_pdf, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    storagePath!.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : onClear,
                  child: Text(isAr ? 'إزالة' : 'Remove'),
                ),
              ],
            )
          else
            Text(
              isAr
                  ? 'اختر ملف PDF من الجهاز (يُفضَّل من الكمبيوتر رفع الملف مباشرة).'
                  : 'Pick a PDF file (on desktop, uploading the file is preferred).',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: (busy || uploading) ? null : onPick,
            icon: uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined),
            label: Text(
              uploading
                  ? (isAr ? 'جاري الرفع…' : 'Uploading…')
                  : (isAr ? 'رفع PDF' : 'Upload PDF'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final bool isAr;
  final String? marketerPublishName;

  const _HeaderCard({
    required this.isAr,
    required this.marketerPublishName,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = (marketerPublishName ?? '').trim();

    final base = FieldGroupTheme.boxDecoration(context);
    return Container(
      decoration: BoxDecoration(
        color: base.color,
        borderRadius: base.borderRadius,
        border: base.border,
        boxShadow: [
          BoxShadow(
            blurRadius: 8,
            offset: const Offset(0, 4),
            color: cs.shadow.withOpacity(0.1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.add_home_work_outlined,
              color: Color(0xFF0F766E),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: name.isEmpty
                ? Text(
                    isAr ? 'إضافة إعلان' : 'Add listing',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr ? 'نشر بواسطة' : 'Published by',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ListingMediaCard extends StatelessWidget {
  final bool isAr;
  final List<_PickedImage> images;
  final bool saving;
  final bool picking;
  final bool uploadingVideo;
  final bool hasVideo;
  final bool showCoverHeroPicker;
  final bool coverHeroIsVideo;
  final ValueChanged<bool> onCoverHeroIsVideoChanged;
  final VoidCallback onPickImages;
  final VoidCallback onPickVideo;
  final VoidCallback onClearVideo;
  final void Function(int i) onRemoveImage;
  final void Function(int from, int to) onMoveImage;

  const _ListingMediaCard({
    required this.isAr,
    required this.images,
    required this.saving,
    required this.picking,
    required this.uploadingVideo,
    required this.hasVideo,
    required this.showCoverHeroPicker,
    required this.coverHeroIsVideo,
    required this.onCoverHeroIsVideoChanged,
    required this.onPickImages,
    required this.onPickVideo,
    required this.onClearVideo,
    required this.onRemoveImage,
    required this.onMoveImage,
  });

  bool get _busy => saving || picking || uploadingVideo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF0F766E).withOpacity(0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 12,
            offset: const Offset(0, 4),
            color: const Color(0xFF0F766E).withOpacity(0.08),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.collections_outlined, color: const Color(0xFF0F766E)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr ? 'ابدأ بالوسائط' : 'Start with media',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isAr
                          ? 'أضف صورة واحدة على الأقل أو فيديو، ثم أكمل بقية الحقول أدناه.'
                          : 'Add at least one image or a video, then fill the rest of the form below.',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 520;
              final imgBtn = FilledButton.icon(
                onPressed: _busy ? null : onPickImages,
                icon: picking
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: AppLogoLoading(compact: true, size: 16),
                      )
                    : const Icon(Icons.add_photo_alternate_outlined),
                label: Text(isAr ? 'إضافة صور' : 'Add images'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                ),
              );
              final vidBtn = OutlinedButton.icon(
                onPressed: (_busy || uploadingVideo) ? null : onPickVideo,
                icon: uploadingVideo
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: AppLogoLoading(compact: true, size: 16),
                      )
                    : const Icon(Icons.video_library_outlined),
                label: Text(isAr ? 'إضافة فيديو' : 'Add video'),
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    imgBtn,
                    const SizedBox(height: 8),
                    vidBtn,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: imgBtn),
                  const SizedBox(width: 10),
                  Expanded(child: vidBtn),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (hasVideo || uploadingVideo)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.play_circle_outline,
                    color: cs.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      uploadingVideo
                          ? (isAr ? 'جارٍ رفع الفيديو…' : 'Uploading video…')
                          : (isAr
                              ? 'تم إرفاق فيديو للإعلان (فيديو واحد كحد أقصى).'
                              : 'A listing video is attached (max one).'),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  if (hasVideo && !_busy)
                    TextButton(
                      onPressed: onClearVideo,
                      child: Text(isAr ? 'إزالة' : 'Remove'),
                    ),
                ],
              ),
            ),
          if (hasVideo || uploadingVideo) const SizedBox(height: 12),
          if (images.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.image_outlined, color: cs.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isAr
                          ? 'لا توجد صور بعد — يمكنك الاعتماد على الفيديو فقط أو إضافة صور.'
                          : 'No images yet — you can use video only or add photos.',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ),
                ],
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(images.length, (i) {
                  return _ImageThumb(
                    bytes: images[i].bytes,
                    index: i,
                    total: images.length,
                    isAr: isAr,
                    onRemove: _busy ? null : () => onRemoveImage(i),
                    onMoveLeft:
                        _busy || i == 0 ? null : () => onMoveImage(i, i - 1),
                    onMoveRight: _busy || i == images.length - 1
                        ? null
                        : () => onMoveImage(i, i + 1),
                  );
                }),
              ),
            ),
          if (images.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              isAr
                  ? 'الصورة الأولى في القائمة هي غلاف الإعلان (ما لم تختر الفيديو كغلاف عند وجوده).'
                  : 'The first image is the cover (unless you choose video as cover when both exist).',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
          if (showCoverHeroPicker) ...[
            const SizedBox(height: 14),
            Text(
              isAr ? 'ما يظهر أولاً في المعرض' : 'Gallery lead',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: <ButtonSegment<bool>>[
                ButtonSegment<bool>(
                  value: true,
                  label: Text(isAr ? 'فيديو' : 'Video'),
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                ),
                ButtonSegment<bool>(
                  value: false,
                  label: Text(isAr ? 'صورة' : 'Image'),
                  icon: const Icon(Icons.image_outlined, size: 18),
                ),
              ],
              selected: <bool>{coverHeroIsVideo},
              onSelectionChanged: (Set<bool> next) {
                if (_busy || next.isEmpty) return;
                onCoverHeroIsVideoChanged(next.first);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _ImageThumb extends StatelessWidget {
  final Uint8List bytes;
  final int index;
  final int total;
  final bool isAr;
  final VoidCallback? onRemove;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;

  const _ImageThumb({
    required this.bytes,
    required this.index,
    required this.total,
    required this.isAr,
    this.onRemove,
    this.onMoveLeft,
    this.onMoveRight,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.memory(bytes, fit: BoxFit.cover),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    index == 0 ? (isAr ? 'غلاف' : 'Cover') : '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: isAr ? 'يسار' : 'Left',
                onPressed: onMoveLeft,
                icon: const Icon(Icons.chevron_left),
                iconSize: 20,
              ),
              IconButton(
                tooltip: isAr ? 'حذف' : 'Remove',
                onPressed: onRemove,
                icon: Icon(Icons.delete_outline, color: cs.error),
                iconSize: 20,
              ),
              IconButton(
                tooltip: isAr ? 'يمين' : 'Right',
                onPressed: onMoveRight,
                icon: const Icon(Icons.chevron_right),
                iconSize: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoordsCard extends StatelessWidget {
  final bool isAr;
  final bool saving;
  final bool enabled;
  final bool locationIsApproximate;
  final TextEditingController latController;
  final TextEditingController lngController;
  final double? lat;
  final double? lng;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPick;
  final ValueChanged<String> onLatChanged;
  final ValueChanged<String> onLngChanged;
  final GlobalKey<FormState>? formKey;

  const _CoordsCard({
    required this.isAr,
    required this.saving,
    required this.enabled,
    this.locationIsApproximate = false,
    required this.latController,
    required this.lngController,
    required this.lat,
    required this.lng,
    required this.onToggle,
    required this.onPick,
    required this.onLatChanged,
    required this.onLngChanged,
    this.formKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final has = lat != null && lng != null;

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isAr ? 'الموقع من الخريطة' : 'Map location',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Switch(value: enabled, onChanged: saving ? null : onToggle),
          ],
        ),
        if (enabled) ...[
          const SizedBox(height: 4),
          Text(
            isAr
                ? 'بعد النقطة: تُملأ المنطقة والمدينة في الخطوة التالية (قابلة للتعديل).'
                : 'After the point: region/city fill in the next step (editable).',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
              height: 1.25,
            ),
          ),
        ],
        if (enabled && has) ...[
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Chip(
              avatar: Icon(
                locationIsApproximate
                    ? Icons.my_location_outlined
                    : Icons.location_on_outlined,
                size: 18,
                color: locationIsApproximate
                    ? cs.tertiary
                    : const Color(0xFF0F766E),
              ),
              label: Text(
                locationIsApproximate
                    ? (isAr ? 'موقع تقريبي' : 'Approximate location')
                    : (isAr ? 'موقع محدد' : 'Exact location'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              backgroundColor: (locationIsApproximate
                      ? cs.tertiaryContainer
                      : const Color(0xFFCCFBF1))
                  .withValues(alpha: 0.65),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: (!enabled || saving) ? null : onPick,
            icon: const Icon(Icons.map_outlined),
            label: Text(
              has
                  ? (isAr ? 'تعديل النقطة على الخريطة' : 'Adjust map point')
                  : (isAr ? 'اختر نقطة على الخريطة' : 'Pick on map'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
          ),
        ),
        if (enabled) ...[
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 560;

              final latField = AqarTextFormField(
                controller: latController,
                enabled: !saving,
                onChanged: onLatChanged,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: isAr ? 'N (°)' : 'N (°)',
                ),
                validator: (v) {
                  if (!enabled) return null;
                  final s =
                      _AddPropertyPageState.normalizeNumbers(v ?? '').trim();
                  if (s.isEmpty) {
                    return isAr ? 'مطلوب' : 'Required';
                  }
                  if (double.tryParse(s) == null) {
                    return isAr ? 'رقم غير صحيح' : 'Invalid number';
                  }
                  return null;
                },
              );

              final lngField = AqarTextFormField(
                controller: lngController,
                enabled: !saving,
                onChanged: onLngChanged,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: isAr ? 'E (°)' : 'E (°)',
                ),
                validator: (v) {
                  if (!enabled) return null;
                  final s =
                      _AddPropertyPageState.normalizeNumbers(v ?? '').trim();
                  if (s.isEmpty) {
                    return isAr ? 'مطلوب' : 'Required';
                  }
                  if (double.tryParse(s) == null) {
                    return isAr ? 'رقم غير صحيح' : 'Invalid number';
                  }
                  return null;
                },
              );

              if (narrow) {
                return Column(
                  children: [
                    latField,
                    const SizedBox(height: 10),
                    lngField,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: latField),
                  const SizedBox(width: 10),
                  Expanded(child: lngField),
                ],
              );
            },
          ),
        ],
      ],
    );

    return Container(
      decoration: FieldGroupTheme.boxDecoration(context),
      padding: const EdgeInsets.all(16),
      child: formKey != null
          ? Form(
              key: formKey,
              child: column,
            )
          : column,
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String text;
  final bool isAr;

  const _ErrorBox({
    required this.text,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.errorContainer.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: cs.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: cs.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickedImage {
  final String name;
  final Uint8List bytes;

  const _PickedImage({
    required this.name,
    required this.bytes,
  });
}

// =======================
// Form Card - النموذج الرئيسي
// =======================

/// إقرار قانوني + صفة المعلن الفعلية (من نوع الحساب) قبل الموافقة على الشروط.
class _DealPublishExtrasCard extends StatelessWidget {
  final bool isAr;
  final bool saving;
  final bool noLegalObstacles;
  final ValueChanged<bool> onNoLegalObstaclesChanged;
  final String advertiserRoleLabel;

  const _DealPublishExtrasCard({
    required this.isAr,
    required this.saving,
    required this.noLegalObstacles,
    required this.onNoLegalObstaclesChanged,
    required this.advertiserRoleLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: FieldGroupTheme.boxDecoration(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isAr ? 'تأكيدات قبل النشر' : 'Confirmations before publish',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            value: noLegalObstacles,
            onChanged: saving
                ? null
                : (v) => onNoLegalObstaclesChanged(v == true),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(
              isAr
                  ? 'أقر بأن العقار خالٍ مما يمنع التصرف أو الانتفاع به'
                  : 'I confirm nothing prevents disposal or use of the property',
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isAr ? 'صفة مقدم الإعلان' : 'Advertiser capacity',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            child: Row(
              children: [
                Icon(Icons.badge_outlined, color: cs.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    advertiserRoleLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  final bool isAr;
  final GlobalKey<FormState> formKey;
  final bool saving;
  final AddPropertyFormSlice slice;
  final int wizardPaneKind;
  final bool marketingSimplifiedForm;
  final String primaryPurposeGroup;
  final ValueChanged<String> onPrimaryPurposeGroupChanged;
  final String propertyCategory;
  final ValueChanged<String> onPropertyCategoryChanged;
  final String? subPurposeCode;
  final ValueChanged<String?> onSubPurposeCodeChanged;
  final bool? propertyHasObligations;
  final ValueChanged<bool?> onPropertyHasObligationsChanged;
  final TextEditingController obligationsDetail;
  final bool autoFillTitle;

  static void _noopPurposeGroup(String _) {}
  static void _noopCategory(String _) {}
  static void _noopSubPurpose(String? _) {}
  static void _noopObligations(bool? _) {}

  final bool locationsLoading;
  final TextEditingController regionController;
  final TextEditingController governorateController;
  final TextEditingController cityController;
  final TextEditingController locationController;
  final TextEditingController addressLineController;

  final bool regionManual;
  final bool governorateManual;
  final bool cityManual;
  final bool districtManual;
  final String? selectedDistrict;
  final List<String> districtOptions;
  final Future<void> Function(String?) onDistrictSelected;
  final ValueChanged<bool> onDistrictManualChanged;
  final String? selectedRegion;
  final String? selectedGovernorate;
  final String? selectedCity;
  final List<String> regionOptions;
  final List<String> governorateOptions;
  final List<String> cityOptions;
  final Future<void> Function(String?) onRegionSelected;
  final Future<void> Function(String?) onGovernorateSelected;
  final Future<void> Function(String?) onCitySelected;
  final ValueChanged<bool> onRegionManualChanged;
  final ValueChanged<bool> onGovernorateManualChanged;
  final ValueChanged<bool> onCityManualChanged;

  final TextEditingController boundaryNorth;
  final TextEditingController boundarySouth;
  final TextEditingController boundaryEast;
  final TextEditingController boundaryWest;

  final String type;
  final String purpose;
  final List<Map<String, String>> purposeTypes;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onPurposeChanged;
  final bool usageResidential;
  final bool usageCommercial;
  final ValueChanged<bool> onUsageResidentialChanged;
  final ValueChanged<bool> onUsageCommercialChanged;

  final TextEditingController title;
  final TextEditingController desc;
  final TextEditingController area;
  final TextEditingController price;
  final ListingAreaUnit areaUnit;
  final ValueChanged<ListingAreaUnit> onAreaUnitChanged;
  final double? computedPricePerSqm;

  // ----- فوترة: ضريبة 5% + عمولة تسويق -----
  final bool? priceIncludesVat;
  final ValueChanged<bool> onPriceIncludesVatChanged;
  final String commissionKind; // none | percent | fixed
  final ValueChanged<String> onCommissionKindChanged;
  final TextEditingController commissionFixedCtrl;
  final ListingInvoiceModel liveInvoice;

  final String currency;
  final bool negotiable;
  final ValueChanged<String> onCurrencyChanged;
  final ValueChanged<bool> onNegotiableChanged;

  final bool isAuction;
  final TextEditingController currentBid;
  final ValueChanged<bool> onAuctionChanged;

  final int? bedrooms;
  final int? bathrooms;
  final int? parkingSpots;
  final bool furnished;
  final int? yearBuilt;
  final int? floor;
  final int? totalFloors;

  final ValueChanged<int?> onBedroomsChanged;
  final ValueChanged<int?> onBathroomsChanged;
  final ValueChanged<int?> onParkingChanged;
  final ValueChanged<bool> onFurnishedChanged;
  final ValueChanged<int?> onYearBuiltChanged;
  final ValueChanged<int?> onFloorChanged;
  final ValueChanged<int?> onTotalFloorsChanged;

  final Map<String, bool> amenities;
  final void Function(String, bool) onAmenityToggle;

  final bool requiresDeed;
  final TextEditingController deedNumber;
  final TextEditingController deedIssuer;
  final DateTime? deedDate;
  final VoidCallback onPickDeedDate;
  final VoidCallback onClearDeedDate;
  final TextEditingController buildingNumber;
  final bool showBuildingNumber;
  final TextEditingController virtualTourUrl;
  final DateTime? availabilityDate;
  final VoidCallback onPickAvailability;
  final VoidCallback onClearAvailability;

  final int? livingRooms;
  final int? kitchens;
  final bool hasElevator;
  final bool independentEntrance;
  final bool hasCentralAc;
  final bool hasSplitAc;
  final ValueChanged<int?> onLivingRoomsChanged;
  final ValueChanged<int?> onKitchensChanged;
  final ValueChanged<bool> onHasElevatorChanged;
  final ValueChanged<bool> onIndependentEntranceChanged;
  final ValueChanged<bool> onHasCentralAcChanged;
  final ValueChanged<bool> onHasSplitAcChanged;

  final int? majlisCount;
  final int? annexCount;
  final bool hasGarden;
  final bool hasPool;
  final bool hasCourtyard;
  final bool carEntrance;
  final bool internalStair;
  final bool separateApartment;
  final bool hasDriverRoom;
  final bool hasMaidRoom;
  final bool hasStorageRoom;
  final ValueChanged<int?> onMajlisCountChanged;
  final ValueChanged<int?> onAnnexCountChanged;
  final ValueChanged<bool> onHasGardenChanged;
  final ValueChanged<bool> onHasPoolChanged;
  final ValueChanged<bool> onHasCourtyardChanged;
  final ValueChanged<bool> onCarEntranceChanged;
  final ValueChanged<bool> onInternalStairChanged;
  final ValueChanged<bool> onSeparateApartmentChanged;
  final ValueChanged<bool> onHasDriverRoomChanged;
  final ValueChanged<bool> onHasMaidRoomChanged;
  final ValueChanged<bool> onHasStorageRoomChanged;

  final int? floorsCount;
  final int? unitsCount;
  final double? plotArea;
  final bool hasLoadingDock;
  final bool hasCrane;
  final String? projectType;
  final ValueChanged<int?> onFloorsCountChanged;
  final ValueChanged<int?> onUnitsCountChanged;
  final ValueChanged<double?> onPlotAreaChanged;
  final ValueChanged<bool> onHasLoadingDockChanged;
  final ValueChanged<bool> onHasCraneChanged;
  final ValueChanged<String?> onProjectTypeChanged;

  final String? landUse;
  final String? facade;
  final int? streetCount;
  final TextEditingController streetWidth1;
  final TextEditingController streetWidth2;
  final TextEditingController streetWidth3;
  final TextEditingController streetWidth4;
  final bool isCornerLand;
  final TextEditingController planNumber;
  final TextEditingController parcelNumber;
  final ValueChanged<String?> onLandUseChanged;
  final ValueChanged<String?> onFacadeChanged;
  final ValueChanged<int?> onStreetCountChanged;
  final ValueChanged<bool> onIsCornerLandChanged;

  // إضافة الخصائص الجديدة للتصنيف
  final bool isLand;
  final bool isProject;
  final bool isWarehouse;
  final bool isBuilding;
  final bool showResidentialBedBath;
  final bool showParkingYearRow;
  final bool showFurnishedRow;
  final bool showFloorFieldsRow;

  /// سعر محدد مقابل «على السوم» (أسلوب Deal).
  final bool priceOnSum;
  final ValueChanged<bool>? onPriceOnSumChanged;
  final bool acceptsMortgageFinance;
  final ValueChanged<bool>? onAcceptsMortgageFinanceChanged;
  final String? propertyAgeBucket;
  final ValueChanged<String?>? onPropertyAgeBucketChanged;
  final VoidCallback? onSuggestSmartTitle;

  /// اختيار سريع للمدن (الرياض / جدة / مكة) — يُمرَّر فقط لشريحة الموقع.
  const _FormCard({
    required this.isAr,
    required this.formKey,
    required this.saving,
    required this.slice,
    this.wizardPaneKind = 1,
    this.marketingSimplifiedForm = false,
    this.primaryPurposeGroup = 'sale',
    this.onPrimaryPurposeGroupChanged = _noopPurposeGroup,
    this.propertyCategory = 'residential',
    this.onPropertyCategoryChanged = _noopCategory,
    this.subPurposeCode,
    this.onSubPurposeCodeChanged = _noopSubPurpose,
    this.propertyHasObligations,
    this.onPropertyHasObligationsChanged = _noopObligations,
    required this.obligationsDetail,
    this.autoFillTitle = false,
    required this.locationsLoading,
    required this.regionController,
    required this.governorateController,
    required this.cityController,
    required this.locationController,
    required this.addressLineController,
    required this.regionManual,
    required this.governorateManual,
    required this.cityManual,
    required this.districtManual,
    required this.selectedDistrict,
    required this.districtOptions,
    required this.onDistrictSelected,
    required this.onDistrictManualChanged,
    required this.selectedRegion,
    required this.selectedGovernorate,
    required this.selectedCity,
    required this.regionOptions,
    required this.governorateOptions,
    required this.cityOptions,
    required this.onRegionSelected,
    required this.onGovernorateSelected,
    required this.onCitySelected,
    required this.onRegionManualChanged,
    required this.onGovernorateManualChanged,
    required this.onCityManualChanged,
    required this.boundaryNorth,
    required this.boundarySouth,
    required this.boundaryEast,
    required this.boundaryWest,
    required this.type,
    required this.purpose,
    required this.purposeTypes,
    required this.onTypeChanged,
    required this.onPurposeChanged,
    required this.usageResidential,
    required this.usageCommercial,
    required this.onUsageResidentialChanged,
    required this.onUsageCommercialChanged,
    required this.title,
    required this.desc,
    required this.area,
    required this.price,
    required this.areaUnit,
    required this.onAreaUnitChanged,
    required this.computedPricePerSqm,
    required this.priceIncludesVat,
    required this.onPriceIncludesVatChanged,
    required this.commissionKind,
    required this.onCommissionKindChanged,
    required this.commissionFixedCtrl,
    required this.liveInvoice,
    required this.currency,
    required this.negotiable,
    required this.onCurrencyChanged,
    required this.onNegotiableChanged,
    required this.isAuction,
    required this.currentBid,
    required this.onAuctionChanged,
    required this.bedrooms,
    required this.bathrooms,
    required this.parkingSpots,
    required this.furnished,
    required this.yearBuilt,
    required this.floor,
    required this.totalFloors,
    required this.onBedroomsChanged,
    required this.onBathroomsChanged,
    required this.onParkingChanged,
    required this.onFurnishedChanged,
    required this.onYearBuiltChanged,
    required this.onFloorChanged,
    required this.onTotalFloorsChanged,
    required this.amenities,
    required this.onAmenityToggle,
    required this.requiresDeed,
    required this.deedNumber,
    required this.deedIssuer,
    required this.deedDate,
    required this.onPickDeedDate,
    required this.onClearDeedDate,
    required this.buildingNumber,
    required this.showBuildingNumber,
    required this.virtualTourUrl,
    required this.availabilityDate,
    required this.onPickAvailability,
    required this.onClearAvailability,
    required this.livingRooms,
    required this.kitchens,
    required this.hasElevator,
    required this.independentEntrance,
    required this.hasCentralAc,
    required this.hasSplitAc,
    required this.onLivingRoomsChanged,
    required this.onKitchensChanged,
    required this.onHasElevatorChanged,
    required this.onIndependentEntranceChanged,
    required this.onHasCentralAcChanged,
    required this.onHasSplitAcChanged,
    required this.majlisCount,
    required this.annexCount,
    required this.hasGarden,
    required this.hasPool,
    required this.hasCourtyard,
    required this.carEntrance,
    required this.internalStair,
    required this.separateApartment,
    required this.hasDriverRoom,
    required this.hasMaidRoom,
    required this.hasStorageRoom,
    required this.onMajlisCountChanged,
    required this.onAnnexCountChanged,
    required this.onHasGardenChanged,
    required this.onHasPoolChanged,
    required this.onHasCourtyardChanged,
    required this.onCarEntranceChanged,
    required this.onInternalStairChanged,
    required this.onSeparateApartmentChanged,
    required this.onHasDriverRoomChanged,
    required this.onHasMaidRoomChanged,
    required this.onHasStorageRoomChanged,
    required this.floorsCount,
    required this.unitsCount,
    required this.plotArea,
    required this.hasLoadingDock,
    required this.hasCrane,
    required this.projectType,
    required this.onFloorsCountChanged,
    required this.onUnitsCountChanged,
    required this.onPlotAreaChanged,
    required this.onHasLoadingDockChanged,
    required this.onHasCraneChanged,
    required this.onProjectTypeChanged,
    required this.landUse,
    required this.facade,
    required this.streetCount,
    required this.streetWidth1,
    required this.streetWidth2,
    required this.streetWidth3,
    required this.streetWidth4,
    required this.isCornerLand,
    required this.planNumber,
    required this.parcelNumber,
    required this.onLandUseChanged,
    required this.onFacadeChanged,
    required this.onStreetCountChanged,
    required this.onIsCornerLandChanged,
    required this.isLand,
    required this.isProject,
    required this.isWarehouse,
    required this.isBuilding,
    required this.showResidentialBedBath,
    required this.showParkingYearRow,
    required this.showFurnishedRow,
    required this.showFloorFieldsRow,
    this.priceOnSum = false,
    this.onPriceOnSumChanged,
    this.acceptsMortgageFinance = false,
    this.onAcceptsMortgageFinanceChanged,
    this.propertyAgeBucket,
    this.onPropertyAgeBucketChanged,
    this.onSuggestSmartTitle,
  });

  String _label(Map<String, String> item) =>
      isAr ? (item['ar'] ?? '') : (item['en'] ?? '');

  List<DropdownMenuItem<String>> _menuFromOptions(List<String> items) {
    return items
        .map((e) => DropdownMenuItem<String>(
              value: e,
              child: Text(e),
            ))
        .toList();
  }

  List<DropdownMenuItem<int>> _intItems(int from, int to) {
    return List.generate(
      to - from + 1,
      (i) => from + i,
    )
        .map((e) => DropdownMenuItem<int>(
              value: e,
              child: Text('$e'),
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
        );

    const kLocSearch = 6;

    final regionDropdownItems = _menuFromOptions(regionOptions);

    final governorateDropdownItems = _menuFromOptions(governorateOptions);

    final cityDropdownItems = _menuFromOptions(cityOptions);

    final districtDropdownItems = _menuFromOptions(districtOptions);

    const kDistrictSearch = 15;

    return Container(
      decoration: FieldGroupTheme.boxDecoration(context),
      padding: const EdgeInsets.all(16),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _formSliceTitle(slice, isAr),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _formSliceHint(slice, isAr),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: cs.primary,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            if (slice == AddPropertyFormSlice.classification) ...[
              if (wizardPaneKind == 101) ...[
                Text(
                  isAr ? 'نوع الإعلان' : 'Listing type',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'sale',
                      label: Text(isAr ? 'بيع' : 'Sale'),
                    ),
                    ButtonSegment(
                      value: 'rent',
                      label: Text(isAr ? 'إيجار' : 'Rent'),
                    ),
                    ButtonSegment(
                      value: 'purchase',
                      label: Text(isAr ? 'شراء' : 'Purchase'),
                    ),
                  ],
                  selected: {primaryPurposeGroup},
                  onSelectionChanged: saving
                      ? null
                      : (s) => onPrimaryPurposeGroupChanged(s.first),
                ),
              ] else if (wizardPaneKind == 102) ...[
                Text(
                  isAr ? 'نوع العقار' : 'Property type',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                PropertyTypeHierarchyPicker(
                  value: type,
                  isAr: isAr,
                  saving: saving,
                  onChanged: onTypeChanged,
                ),
              ] else if (marketingSimplifiedForm) ...[
                DropdownButtonFormField<String>(
                  value: propertyCategory,
                  decoration: deco(isAr ? 'تصنيف العقار' : 'Property category'),
                  items: MarketingAddPropertyFlowConfig.propertyCategoryOptions
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e['code'],
                          child: Text(isAr ? e['ar']! : e['en']!),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (v) {
                          if (v != null) onPropertyCategoryChanged(v);
                        },
                ),
                const SizedBox(height: 12),
                PropertyTypeHierarchyPicker(
                  value: type,
                  isAr: isAr,
                  saving: saving,
                  onChanged: onTypeChanged,
                ),
                const SizedBox(height: 12),
                Text(
                  isAr ? 'الغرض' : 'Purpose',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'sale',
                      label: Text(isAr ? 'بيع' : 'Sale'),
                    ),
                    ButtonSegment(
                      value: 'rent',
                      label: Text(isAr ? 'إيجار' : 'Rent'),
                    ),
                  ],
                  selected: {primaryPurposeGroup == 'rent' ? 'rent' : 'sale'},
                  onSelectionChanged: saving
                      ? null
                      : (s) => onPrimaryPurposeGroupChanged(s.first),
                ),
                const SizedBox(height: 10),
                if (primaryPurposeGroup == 'rent')
                  DropdownButtonFormField<String>(
                    value: subPurposeCode ??
                        (purpose.startsWith('daily')
                            ? 'daily_rent'
                            : purpose.startsWith('yearly')
                                ? 'yearly_rent'
                                : 'monthly_rent'),
                    decoration: deco(isAr ? 'مدة الإيجار' : 'Rent term'),
                    items: [
                      DropdownMenuItem(
                        value: 'daily_rent',
                        child: Text(isAr ? 'يومي' : 'Daily'),
                      ),
                      DropdownMenuItem(
                        value: 'monthly_rent',
                        child: Text(isAr ? 'شهري' : 'Monthly'),
                      ),
                      DropdownMenuItem(
                        value: 'yearly_rent',
                        child: Text(isAr ? 'سنوي' : 'Yearly'),
                      ),
                    ],
                    onChanged: saving ? null : onSubPurposeCodeChanged,
                  )
                else
                  DropdownButtonFormField<String>(
                    value: subPurposeCode ??
                        (purpose == 'auction'
                            ? 'auction'
                            : purpose == 'investment'
                                ? 'investment'
                                : 'sale'),
                    decoration: deco(isAr ? 'نوع البيع' : 'Sale type'),
                    items: [
                      DropdownMenuItem(
                        value: 'sale',
                        child: Text(isAr ? 'بيع' : 'Sale'),
                      ),
                      DropdownMenuItem(
                        value: 'auction',
                        child: Text(isAr ? 'مزاد' : 'Auction'),
                      ),
                      DropdownMenuItem(
                        value: 'investment',
                        child: Text(isAr ? 'استثمار' : 'Investment'),
                      ),
                    ],
                    onChanged: saving ? null : onSubPurposeCodeChanged,
                  ),
                const SizedBox(height: 14),
                Text(
                  isAr ? 'هل على العقار التزامات؟' : 'Property obligations?',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    StableSelectChip(
                      label: isAr ? 'نعم' : 'Yes',
                      exclusive: true,
                      selected: propertyHasObligations == true,
                      enabled: !saving,
                      onSelected: (_) =>
                          onPropertyHasObligationsChanged(true),
                    ),
                    StableSelectChip(
                      label: isAr ? 'لا' : 'No',
                      exclusive: true,
                      selected: propertyHasObligations == false,
                      enabled: !saving,
                      onSelected: (_) =>
                          onPropertyHasObligationsChanged(false),
                    ),
                  ],
                ),
                if (propertyHasObligations == true) ...[
                  const SizedBox(height: 8),
                  AqarTextFormField(
                    controller: obligationsDetail,
                    enabled: !saving,
                    minLines: 2,
                    maxLines: 4,
                    decoration: deco(
                      isAr ? 'تفاصيل الالتزامات' : 'Obligation details',
                    ),
                  ),
                ],
              ] else ...[
              // 1. نوع العقار (هرمي: مجموعة + فرعي)
              PropertyTypeHierarchyPicker(
                value: type,
                isAr: isAr,
                saving: saving,
                onChanged: onTypeChanged,
              ),
              const SizedBox(height: 12),

              Text(
                isAr ? 'هل العقار مناسب لـ:' : 'Property is suitable for:',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  StableSelectChip(
                    label: isAr ? 'سكني' : 'Residential',
                    selected: usageResidential,
                    enabled: !saving,
                    onSelected: onUsageResidentialChanged,
                    selectedColor:
                        const Color(0xFF0F766E).withOpacity(0.22),
                    checkColor: const Color(0xFF0F766E),
                  ),
                  StableSelectChip(
                    label: isAr ? 'تجاري' : 'Commercial',
                    selected: usageCommercial,
                    enabled: !saving,
                    onSelected: onUsageCommercialChanged,
                    selectedColor:
                        const Color(0xFF0F766E).withOpacity(0.22),
                    checkColor: const Color(0xFF0F766E),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 2. الغرض
              Text(
                isAr ? 'الغرض (بيع / إيجار / …)' : 'Purpose (sale / rent / …)',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: purposeTypes.map((e) {
                    final code = e['code']!;
                    final sel = purpose == code;
                    final col = _purposeAccentColor(code);
                    return Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: StableSelectChip(
                        label: _label(e),
                        exclusive: true,
                        selected: sel,
                        enabled: !saving,
                        onSelected: (_) => onPurposeChanged(code),
                        selectedColor: col.withOpacity(0.22),
                        checkColor: col,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: purpose,
                items: purposeTypes
                    .map(
                      (e) => DropdownMenuItem<String>(
                        value: e['code'],
                        child: Text(_label(e)),
                      ),
                    )
                    .toList(),
                onChanged: saving
                    ? null
                    : (v) {
                        if (v != null) onPurposeChanged(v);
                      },
                decoration: deco(isAr ? 'الغرض (قائمة)' : 'Purpose (list)'),
              ),
              const SizedBox(height: 12),
              ],
            ],
            if (slice == AddPropertyFormSlice.location) ...[
              if (locationsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                ),

              // 5. المنطقة
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 700;

                  final Widget regionField;
                  if (regionManual) {
                    regionField = AqarTextFormField(
                      controller: regionController,
                      enabled: !saving,
                      decoration: deco(isAr ? 'المنطقة' : 'Region'),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) {
                          return isAr ? 'مطلوب' : 'Required';
                        }
                        return null;
                      },
                    );
                  } else if (regionOptions.length > kLocSearch) {
                    regionField = FormField<String>(
                      validator: (_) => regionController.text.trim().isEmpty
                          ? (isAr ? 'مطلوب' : 'Required')
                          : null,
                      builder: (state) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SearchableSelectField(
                              label: isAr ? 'المنطقة' : 'Region',
                              items: regionOptions,
                              selected: selectedRegion,
                              isAr: isAr,
                              enabled: !saving,
                              allowClear: false,
                              onSelected: (v) async {
                                if (v != null) {
                                  await onRegionSelected(v);
                                }
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  state.validate();
                                });
                              },
                              onManualEntry: () {
                                unawaited(
                                    onRegionSelected(_kManualOptionValue));
                              },
                            ),
                            if (state.hasError)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                    top: 6, start: 12),
                                child: Text(
                                  state.errorText!,
                                  style: TextStyle(
                                    color: Theme.of(state.context)
                                        .colorScheme
                                        .error,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  } else {
                    regionField = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          value: selectedRegion != null &&
                                  regionOptions.contains(selectedRegion)
                              ? selectedRegion
                              : null,
                          items: regionDropdownItems,
                          onChanged: saving
                              ? null
                              : (v) {
                                  if (v != null) {
                                    unawaited(onRegionSelected(v));
                                  }
                                },
                          decoration: deco(isAr ? 'المنطقة' : 'Region'),
                          validator: (_) {
                            if ((regionController.text).trim().isEmpty) {
                              return isAr ? 'مطلوب' : 'Required';
                            }
                            return null;
                          },
                        ),
                        Align(
                          alignment: isAr
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: TextButton(
                            onPressed: saving
                                ? null
                                : () => unawaited(
                                      onRegionSelected(_kManualOptionValue),
                                    ),
                            child: Text(
                              isAr ? 'إدخال يدوي للمنطقة' : 'Manual region',
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  if (narrow) {
                    return Column(
                      children: [
                        regionField,
                      ],
                    );
                  }

                  return regionField;
                },
              ),
              const SizedBox(height: 12),

              // 6. المحافظة
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 700;

                  final Widget governorateField;
                  if (governorateManual) {
                    governorateField = AqarTextFormField(
                      controller: governorateController,
                      enabled: !saving,
                      decoration: deco(isAr ? 'المحافظة' : 'Governorate'),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) {
                          return isAr ? 'مطلوب' : 'Required';
                        }
                        return null;
                      },
                    );
                  } else if (governorateOptions.length > kLocSearch) {
                    governorateField = FormField<String>(
                      validator: (_) =>
                          governorateController.text.trim().isEmpty
                              ? (isAr ? 'مطلوب' : 'Required')
                              : null,
                      builder: (state) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SearchableSelectField(
                              label: isAr ? 'المحافظة' : 'Governorate',
                              items: governorateOptions,
                              selected: selectedGovernorate,
                              isAr: isAr,
                              enabled: !saving,
                              allowClear: false,
                              onSelected: (v) async {
                                if (v != null) {
                                  await onGovernorateSelected(v);
                                }
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  state.validate();
                                });
                              },
                              onManualEntry: () {
                                unawaited(
                                  onGovernorateSelected(_kManualOptionValue),
                                );
                              },
                            ),
                            if (state.hasError)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                    top: 6, start: 12),
                                child: Text(
                                  state.errorText!,
                                  style: TextStyle(
                                    color: Theme.of(state.context)
                                        .colorScheme
                                        .error,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  } else {
                    governorateField = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          value: selectedGovernorate != null &&
                                  governorateOptions
                                      .contains(selectedGovernorate)
                              ? selectedGovernorate
                              : null,
                          items: governorateDropdownItems,
                          onChanged: saving
                              ? null
                              : (v) {
                                  if (v != null) {
                                    unawaited(onGovernorateSelected(v));
                                  }
                                },
                          decoration: deco(isAr ? 'المحافظة' : 'Governorate'),
                          validator: (_) {
                            if ((governorateController.text).trim().isEmpty) {
                              return isAr ? 'مطلوب' : 'Required';
                            }
                            return null;
                          },
                        ),
                        Align(
                          alignment: isAr
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: TextButton(
                            onPressed: saving
                                ? null
                                : () => unawaited(
                                      onGovernorateSelected(
                                        _kManualOptionValue,
                                      ),
                                    ),
                            child: Text(
                              isAr
                                  ? 'إدخال يدوي للمحافظة'
                                  : 'Manual governorate',
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  if (narrow) {
                    return Column(
                      children: [
                        governorateField,
                      ],
                    );
                  }

                  return governorateField;
                },
              ),
              const SizedBox(height: 12),

              // 7. المدينة
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 700;

                  final Widget cityField;
                  if (cityManual) {
                    cityField = AqarTextFormField(
                      controller: cityController,
                      enabled: !saving,
                      decoration: deco(isAr ? 'المدينة' : 'City'),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) {
                          return isAr ? 'مطلوب' : 'Required';
                        }
                        return null;
                      },
                    );
                  } else if (cityOptions.length > kLocSearch) {
                    cityField = FormField<String>(
                      validator: (_) => cityController.text.trim().isEmpty
                          ? (isAr ? 'مطلوب' : 'Required')
                          : null,
                      builder: (state) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SearchableSelectField(
                              label: isAr ? 'المدينة' : 'City',
                              items: cityOptions,
                              selected: selectedCity,
                              isAr: isAr,
                              enabled: !saving,
                              allowClear: false,
                              onSelected: (v) async {
                                if (v != null) {
                                  await onCitySelected(v);
                                }
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  state.validate();
                                });
                              },
                              onManualEntry: () {
                                unawaited(onCitySelected(_kManualOptionValue));
                              },
                            ),
                            if (state.hasError)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                    top: 6, start: 12),
                                child: Text(
                                  state.errorText!,
                                  style: TextStyle(
                                    color: Theme.of(state.context)
                                        .colorScheme
                                        .error,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  } else {
                    cityField = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          value: selectedCity != null &&
                                  cityOptions.contains(selectedCity)
                              ? selectedCity
                              : null,
                          items: cityDropdownItems,
                          onChanged: saving
                              ? null
                              : (v) {
                                  if (v != null) {
                                    unawaited(onCitySelected(v));
                                  }
                                },
                          decoration: deco(isAr ? 'المدينة' : 'City'),
                          validator: (_) {
                            if ((cityController.text).trim().isEmpty) {
                              return isAr ? 'مطلوب' : 'Required';
                            }
                            return null;
                          },
                        ),
                        Align(
                          alignment: isAr
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: TextButton(
                            onPressed: saving
                                ? null
                                : () => unawaited(
                                      onCitySelected(_kManualOptionValue),
                                    ),
                            child: Text(
                              isAr ? 'إدخال يدوي للمدينة' : 'Manual city',
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  if (narrow) {
                    return Column(
                      children: [
                        cityField,
                      ],
                    );
                  }

                  return cityField;
                },
              ),
              const SizedBox(height: 12),

              // 8. الحي
              Text(
                isAr ? 'الحي' : 'District',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (districtOptions.isEmpty)
                AqarTextFormField(
                  controller: locationController,
                  enabled: !saving,
                  decoration: deco(
                    isAr
                        ? 'اسم الحي (اختياري — أدخل يدوياً)'
                        : 'District (optional — type manually)',
                  ),
                )
              else if (districtManual)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AqarTextFormField(
                      controller: locationController,
                      enabled: !saving,
                      decoration:
                          deco(isAr ? 'اسم الحي (يدوي)' : 'District (manual)'),
                    ),
                    Align(
                      alignment:
                          isAr ? Alignment.centerRight : Alignment.centerLeft,
                      child: TextButton(
                        onPressed: saving
                            ? null
                            : () => onDistrictManualChanged(false),
                        child: Text(isAr
                            ? 'العودة لقائمة الأحياء'
                            : 'Use district list'),
                      ),
                    ),
                  ],
                )
              else if (districtOptions.length > kDistrictSearch)
                SearchableSelectField(
                  label: isAr ? 'الحي' : 'District',
                  items: districtOptions,
                  selected: selectedDistrict,
                  isAr: isAr,
                  enabled: !saving,
                  allowClear: false,
                  onSelected: (v) async {
                    if (v != null) {
                      await onDistrictSelected(v);
                    }
                  },
                  onManualEntry: () {
                    unawaited(onDistrictSelected(_kManualOptionValue));
                  },
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedDistrict != null &&
                              districtOptions.contains(selectedDistrict)
                          ? selectedDistrict
                          : null,
                      items: districtDropdownItems,
                      onChanged: saving
                          ? null
                          : (v) {
                              if (v != null) {
                                unawaited(onDistrictSelected(v));
                              }
                            },
                      decoration: deco(isAr ? 'الحي' : 'District'),
                    ),
                    Align(
                      alignment:
                          isAr ? Alignment.centerRight : Alignment.centerLeft,
                      child: TextButton(
                        onPressed: saving
                            ? null
                            : () => unawaited(
                                  onDistrictSelected(_kManualOptionValue),
                                ),
                        child: Text(
                          isAr ? 'إدخال يدوي للحي' : 'Manual district entry',
                        ),
                      ),
                    ),
                  ],
                ),
              if (districtOptions.isNotEmpty && !districtManual) ...[
                const SizedBox(height: 6),
                Align(
                  alignment:
                      isAr ? Alignment.centerRight : Alignment.centerLeft,
                  child: TextButton(
                    onPressed:
                        saving ? null : () => onDistrictManualChanged(true),
                    child: Text(isAr
                        ? 'الحي غير موجود في القائمة'
                        : 'District not in list'),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // حدود القطعة (اختياري)
              Text(
                isAr ? 'حدود القطعة (اختياري)' : 'Parcel boundaries (optional)',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isAr
                    ? 'للأراضي والمخططات؛ يُخزَّن مع بيانات الإرشاد.'
                    : 'For land/plans; stored in listing guidance.',
                style: TextStyle(
                  fontSize: 11.8,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 560;
                  Widget field(TextEditingController ctrl, String lab) {
                    return AqarTextFormField(
                      controller: ctrl,
                      enabled: !saving,
                      decoration: deco(lab),
                    );
                  }

                  final north = field(
                    boundaryNorth,
                    isAr ? 'شمال' : 'North',
                  );
                  final south = field(
                    boundarySouth,
                    isAr ? 'جنوب' : 'South',
                  );
                  final east = field(
                    boundaryEast,
                    isAr ? 'شرق' : 'East',
                  );
                  final west = field(
                    boundaryWest,
                    isAr ? 'غرب' : 'West',
                  );

                  if (narrow) {
                    return Column(
                      children: [
                        north,
                        const SizedBox(height: 8),
                        south,
                        const SizedBox(height: 8),
                        east,
                        const SizedBox(height: 8),
                        west,
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: north),
                          const SizedBox(width: 8),
                          Expanded(child: south),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: east),
                          const SizedBox(width: 8),
                          Expanded(child: west),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),

              if (showBuildingNumber) ...[
                AqarTextFormField(
                  controller: buildingNumber,
                  enabled: !saving,
                  decoration: deco(isAr
                      ? 'رقم المبنى (اختياري)'
                      : 'Building number (optional)'),
                ),
                const SizedBox(height: 12),
              ],

              // 9. العنوان الوطني
              AqarTextFormField(
                controller: addressLineController,
                enabled: !saving,
                decoration: deco(isAr
                    ? 'العنوان الوطني (اختياري)'
                    : 'National address (optional)'),
              ),
              const SizedBox(height: 12),
            ],
            if (slice == AddPropertyFormSlice.pricing) ...[
              // بيانات الصك والعنوان والوصف (بعد الموقع — كتسلسل الفيديو)
              Text(
                isAr ? 'بيانات الصك' : 'Deed information',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                requiresDeed
                    ? (isAr
                        ? 'إلزامي للبيع والمزاد والاستثمار'
                        : 'Required for sale, auction, and investment')
                    : (isAr
                        ? 'اختياري لعقود الإيجار'
                        : 'Optional for rental listings'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              AqarTextFormField(
                controller: deedNumber,
                enabled: !saving,
                decoration: deco(isAr ? 'رقم الصك' : 'Deed number'),
                validator: (v) {
                  if (!requiresDeed) return null;
                  if (_AddPropertyPageState.normalizeDeedNumber(v ?? '')
                      .isEmpty) {
                    return isAr ? 'مطلوب' : 'Required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 6),
              Text(
                isAr
                    ? 'مراقبة التكرار: لا يُسمح بأكثر من إعلان نشط للبيع/المزاد/الاستثمار بنفس رقم الصك.'
                    : 'Duplicate guard: one active sale/auction/investment listing per deed number.',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              FormField<DateTime>(
                key: ValueKey(
                  deedDate?.millisecondsSinceEpoch ?? 'deed-date-empty',
                ),
                initialValue: deedDate,
                validator: (_) {
                  if (!requiresDeed) return null;
                  if (deedDate == null) {
                    return isAr ? 'مطلوب' : 'Required';
                  }
                  return null;
                },
                builder: (field) {
                  final formatted = deedDate == null
                      ? null
                      : ListingDateDisplay.formatCardDateTime(
                          DateTime(
                            deedDate!.year,
                            deedDate!.month,
                            deedDate!.day,
                          ),
                          isAr: isAr,
                        );
                  return InkWell(
                    onTap: saving ? null : onPickDeedDate,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: deco(isAr ? 'تاريخ الصك' : 'Deed date')
                          .copyWith(
                        errorText: field.errorText,
                        hintText: isAr ? 'اختر التاريخ' : 'Select date',
                        suffixIcon: deedDate != null && !saving
                            ? IconButton(
                                tooltip: isAr ? 'مسح' : 'Clear',
                                onPressed: onClearDeedDate,
                                icon: const Icon(Icons.clear),
                              )
                            : Icon(
                                Icons.calendar_today_outlined,
                                color: cs.onSurfaceVariant,
                              ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          formatted ??
                              (isAr ? 'اختر التاريخ' : 'Select date'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: formatted == null
                                ? cs.onSurfaceVariant
                                : (saving
                                    ? cs.onSurfaceVariant
                                    : cs.onSurface),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              AqarTextFormField(
                controller: deedIssuer,
                enabled: !saving,
                decoration:
                    deco(isAr ? 'الجهة المصدرة للصك' : 'Issuing authority'),
                validator: (v) {
                  if (!requiresDeed) return null;
                  if ((v ?? '').trim().isEmpty) {
                    return isAr ? 'مطلوب' : 'Required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              AqarTextFormField(
                controller: title,
                enabled: !saving && !autoFillTitle,
                readOnly: autoFillTitle,
                decoration: deco(
                  isAr
                      ? (autoFillTitle
                          ? 'عنوان الإعلان (يُعبّأ تلقائياً)'
                          : 'عنوان الإعلان')
                      : (autoFillTitle
                          ? 'Title (auto-filled)'
                          : 'Title'),
                ).copyWith(
                  suffixIcon: (autoFillTitle || onSuggestSmartTitle == null)
                      ? null
                      : IconButton(
                          tooltip: isAr
                              ? 'اقتراح عنوان ذكي'
                              : 'Suggest smart title',
                          onPressed: saving ? null : onSuggestSmartTitle,
                          icon: const Icon(Icons.auto_awesome_outlined),
                        ),
                ),
                validator: (v) {
                  if ((v ?? '').trim().isEmpty) {
                    return isAr ? 'مطلوب' : 'Required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              AqarTextFormField(
                controller: desc,
                enabled: !saving,
                maxLines: 4,
                decoration: deco(isAr ? 'الوصف' : 'Description'),
                validator: (v) {
                  if ((v ?? '').trim().isEmpty) {
                    return isAr ? 'مطلوب' : 'Required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              Text(
                isAr ? 'طريقة التسعير' : 'Pricing mode',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              AbsorbPointer(
                absorbing: saving || onPriceOnSumChanged == null,
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(isAr ? 'سعر محدد' : 'Fixed price'),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(isAr ? 'على السوم' : 'On sum'),
                    ),
                  ],
                  selected: {priceOnSum},
                  onSelectionChanged: (s) => onPriceOnSumChanged?.call(s.first),
                ),
              ),
              const SizedBox(height: 12),

              // 10. المساحة والسعر + أسئلة الضريبة والعمولة + معاينة الفاتورة الحيّة
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 700;

                  final unitField = DropdownButtonFormField<ListingAreaUnit>(
                    value: areaUnit,
                    items: [
                      DropdownMenuItem(
                        value: ListingAreaUnit.m2,
                        child: Text(isAr ? 'م²' : 'm²'),
                      ),
                      DropdownMenuItem(
                        value: ListingAreaUnit.cm2,
                        child: Text(isAr ? 'سم²' : 'cm²'),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (v) {
                            if (v != null) onAreaUnitChanged(v);
                          },
                    decoration: deco(isAr ? 'وحدة المساحة' : 'Area unit'),
                  );

                  final areaField = AqarTextFormField(
                    controller: area,
                    enabled: !saving,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: latinDecimalNumberFormatters(),
                    decoration: deco(isAr ? 'المساحة' : 'Area'),
                    validator: (v) {
                      final s = _AddPropertyPageState.normalizeNumbers(v ?? '')
                          .trim();
                      if (s.isEmpty) return isAr ? 'مطلوب' : 'Required';
                      if (double.tryParse(s) == null) {
                        return isAr ? 'رقم غير صحيح' : 'Invalid number';
                      }
                      return null;
                    },
                  );

                  final priceField = AqarTextFormField(
                    controller: price,
                    enabled: !saving && !priceOnSum,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: latinDecimalNumberFormatters(),
                    decoration: deco(
                      priceOnSum
                          ? (isAr ? 'السعر (على السوم)' : 'Price (on sum)')
                          : (isAr ? 'السعر الإجمالي' : 'Total price'),
                    ),
                    validator: (v) {
                      if (priceOnSum) return null;
                      final s = _AddPropertyPageState.normalizeNumbers(v ?? '')
                          .trim();
                      if (s.isEmpty) return isAr ? 'مطلوب' : 'Required';
                      if (double.tryParse(s) == null) {
                        return isAr ? 'رقم غير صحيح' : 'Invalid number';
                      }
                      return null;
                    },
                  );

                  final ppm = computedPricePerSqm;
                  final ppmTextStyle = TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  );
                  final ppmField = InputDecorator(
                    decoration: deco(
                      isAr ? 'سعر المتر (م²)' : 'Price per m²',
                    ),
                    child: ppm == null
                        ? Text('—', style: ppmTextStyle)
                        : AppMoneyLine(
                            amount: ppm,
                            currencyCode: currency,
                            isAr: isAr,
                            style: ppmTextStyle,
                          ),
                  );

                  final vatQuestion = _VatInclusionQuestion(
                    isAr: isAr,
                    saving: saving,
                    value: priceIncludesVat,
                    onChanged: onPriceIncludesVatChanged,
                  );

                  final commissionQuestion = _CommissionKindQuestion(
                    isAr: isAr,
                    saving: saving,
                    value: commissionKind,
                    onChanged: onCommissionKindChanged,
                    fixedAmountCtrl: commissionFixedCtrl,
                    currencyCode: currency,
                  );

                  final livePreview = (price.text.trim().isEmpty ||
                          priceIncludesVat == null)
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: ListingPricingBreakdown(
                            invoice: liveInvoice,
                            isAr: isAr,
                            title: isAr
                                ? 'معاينة الفاتورة (حسب اختيارك)'
                                : 'Live invoice preview',
                          ),
                        );

                  final stackedHeader = narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(flex: 3, child: areaField),
                                const SizedBox(width: 10),
                                Expanded(flex: 2, child: unitField),
                              ],
                            ),
                            const SizedBox(height: 10),
                            priceField,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 2, child: areaField),
                            const SizedBox(width: 10),
                            Expanded(child: unitField),
                            const SizedBox(width: 10),
                            Expanded(flex: 2, child: priceField),
                          ],
                        );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      stackedHeader,
                      const SizedBox(height: 12),
                      vatQuestion,
                      const SizedBox(height: 10),
                      commissionQuestion,
                      const SizedBox(height: 12),
                      ppmField,
                      livePreview,
                    ],
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  isAr
                      ? 'سعر المتر = السعر الإجمالي ÷ المساحة (بالم²). يستخدم النظام السعر الأساسي (دون الضريبة) في حسابات الفاتورة.'
                      : 'Price/m² = total price ÷ area (m²). Invoice calculations use the base price (excluding VAT).',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // تمويل عقاري (بيع) — أسلوب Deal
              if (!purpose.toLowerCase().contains('rent')) ...[
                SwitchListTile(
                  value: acceptsMortgageFinance,
                  onChanged: saving ? null : onAcceptsMortgageFinanceChanged,
                  title: Text(
                    isAr
                        ? 'يقبل التمويل العقاري / الرهن'
                        : 'Accepts mortgage finance',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
              ],

              // 11. العملة والتفاوض
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 700;

                  final currencyField = DropdownButtonFormField<String>(
                    value: currency,
                    items: const [
                      DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                      DropdownMenuItem(value: 'AED', child: Text('AED')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                    ],
                    onChanged: saving
                        ? null
                        : (v) {
                            if (v != null) onCurrencyChanged(v);
                          },
                    decoration: deco(isAr ? 'العملة' : 'Currency'),
                  );

                  final negotiableField = SwitchListTile(
                    value: negotiable,
                    onChanged: saving ? null : onNegotiableChanged,
                    title: Text(isAr ? 'قابل للتفاوض' : 'Negotiable'),
                    contentPadding: EdgeInsets.zero,
                  );

                  if (narrow) {
                    return Column(
                      children: [
                        currencyField,
                        const SizedBox(height: 4),
                        negotiableField,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: currencyField),
                      const SizedBox(width: 10),
                      Expanded(child: negotiableField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),

              // 12. المزاد
              SwitchListTile(
                value: isAuction,
                onChanged: saving ? null : onAuctionChanged,
                title: Text(
                    isAr ? 'هذا الإعلان مزاد' : 'This listing is an auction'),
                contentPadding: EdgeInsets.zero,
              ),

              if (isAuction) ...[
                const SizedBox(height: 12),
                AqarTextFormField(
                  controller: currentBid,
                  enabled: !saving,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      deco(isAr ? 'السعر الحالي للمزاد' : 'Current bid'),
                  validator: (v) {
                    if (!isAuction) return null;
                    final s =
                        _AddPropertyPageState.normalizeNumbers(v ?? '').trim();
                    if (s.isEmpty) return isAr ? 'مطلوب' : 'Required';
                    if (double.tryParse(s) == null) {
                      return isAr ? 'رقم غير صحيح' : 'Invalid number';
                    }
                    return null;
                  },
                ),
              ],

              const SizedBox(height: 12),
            ],
            if (slice == AddPropertyFormSlice.details) ...[
              // 13. غرف النوم ودورات المياه — إدخال ذكي (أرقام + قائمة).
              if (showResidentialBedBath && !isWarehouse) ...[
                LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 700;
                    final bedroomsField = SmartCountField(
                      label: isAr ? 'غرف النوم' : 'Bedrooms',
                      value: bedrooms,
                      onChanged: saving ? (_) {} : onBedroomsChanged,
                      isAr: isAr,
                      enabled: !saving,
                      min: 0,
                      maxPreset: 12,
                    );
                    final bathroomsField = SmartCountField(
                      label: isAr ? 'دورات المياه' : 'Bathrooms',
                      value: bathrooms,
                      onChanged: saving ? (_) {} : onBathroomsChanged,
                      isAr: isAr,
                      enabled: !saving,
                      min: 0,
                      maxPreset: 12,
                    );
                    if (narrow) {
                      return Column(
                        children: [
                          bedroomsField,
                          const SizedBox(height: 10),
                          bathroomsField,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: bedroomsField),
                        const SizedBox(width: 10),
                        Expanded(child: bathroomsField),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],

              // 14. مواقف السيارات وسنة البناء (سنة البناء إجبارية حتى السنة الحالية).
              if (showParkingYearRow) ...[
                LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 700;

                    final parkingField = SmartCountField(
                      label: isAr ? 'مواقف السيارات' : 'Parking spots',
                      value: parkingSpots,
                      onChanged: saving ? (_) {} : onParkingChanged,
                      isAr: isAr,
                      enabled: !saving,
                      min: 0,
                      maxPreset: 12,
                    );

                    final yearField = YearBuiltPickerField(
                      value: yearBuilt,
                      onChanged: onYearBuiltChanged,
                      enabled: !saving,
                      isAr: isAr,
                      minYear: 1950,
                      maxYear: DateTime.now().year,
                      requiredField: true,
                    );

                    if (narrow) {
                      return Column(
                        children: [
                          parkingField,
                          const SizedBox(height: 10),
                          yearField,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: parkingField),
                        const SizedBox(width: 10),
                        Expanded(child: yearField),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],

              // 15. مفروش
              if (showFurnishedRow && !isWarehouse) ...[
                SwitchListTile(
                  value: furnished,
                  onChanged: saving ? null : onFurnishedChanged,
                  title: Text(isAr ? 'مفروش' : 'Furnished'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),
              ],

              // 16. الطوابق (حسب [PropertyTypeCatalog.showsFloorFields])
              if (showFloorFieldsRow) ...[
                LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 700;

                    final floorField = DropdownButtonFormField<int>(
                      value: floor,
                      items: _intItems(0, 50),
                      onChanged: saving ? null : onFloorChanged,
                      decoration: deco(isAr ? 'الطابق' : 'Floor'),
                    );

                    final totalFloorsField = DropdownButtonFormField<int>(
                      value: totalFloors,
                      items: _intItems(1, 50),
                      onChanged: saving ? null : onTotalFloorsChanged,
                      decoration:
                          deco(isAr ? 'عدد الطوابق الكلي' : 'Total floors'),
                    );

                    if (narrow) {
                      return Column(
                        children: [
                          floorField,
                          const SizedBox(height: 10),
                          totalFloorsField,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: floorField),
                        const SizedBox(width: 10),
                        Expanded(child: totalFloorsField),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],

              // 17. المرافق
              Text(
                isAr ? 'المرافق' : 'Amenities',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: amenities.entries
                    .where((entry) =>
                        !isLand ||
                        PropertyTypeCatalog.amenityKeyRelevantForLand(
                            entry.key))
                    .map((entry) {
                  final key = entry.key;
                  final value = entry.value;
                  final labels = <String, String>{
                    'pool': isAr ? 'مسبح' : 'Pool',
                    'gym': isAr ? 'نادي' : 'Gym',
                    'elevator': isAr ? 'مصعد' : 'Elevator',
                    'security': isAr ? 'أمن' : 'Security',
                    'garden': isAr ? 'حديقة' : 'Garden',
                    'balcony': isAr ? 'شرفة' : 'Balcony',
                    'ac': isAr ? 'تكييف' : 'AC',
                    'parking': isAr ? 'موقف' : 'Parking',
                    'wifi': 'Wi-Fi',
                    'maid_room': isAr ? 'غرفة خادمة' : 'Maid room',
                    'driver_room': isAr ? 'غرفة سائق' : 'Driver room',
                    'storage': isAr ? 'مستودع' : 'Storage',
                    'roof': isAr ? 'سطح' : 'Roof',
                    'kitchen': isAr ? 'مطبخ' : 'Kitchen',
                    'majlis': isAr ? 'مجلس' : 'Majlis',
                    'yard': isAr ? 'حوش' : 'Yard',
                  };

                  return StableSelectChip(
                    label: labels[key] ?? key,
                    selected: value,
                    enabled: !saving,
                    onSelected: (v) => onAmenityToggle(key, v),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // 18. الروابط (الفيديو يُضاف من بطاقة الوسائط أعلى الصفحة)
              AqarTextFormField(
                controller: virtualTourUrl,
                enabled: !saving,
                decoration: deco(isAr
                    ? 'رابط الجولة الافتراضية (اختياري)'
                    : 'Virtual tour URL (optional)'),
              ),
              const SizedBox(height: 12),

              // 19. تاريخ التوفر
              Row(
                children: [
                  Expanded(
                    child: Text(
                      availabilityDate == null
                          ? (isAr
                              ? 'تاريخ التوفر: غير محدد'
                              : 'Availability date: not set')
                          : (isAr
                              ? 'تاريخ التوفر: ${availabilityDate!.year}-${availabilityDate!.month.toString().padLeft(2, '0')}-${availabilityDate!.day.toString().padLeft(2, '0')}'
                              : 'Availability date: ${availabilityDate!.year}-${availabilityDate!.month.toString().padLeft(2, '0')}-${availabilityDate!.day.toString().padLeft(2, '0')}'),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: saving ? null : onPickAvailability,
                    child: Text(isAr ? 'اختيار' : 'Pick'),
                  ),
                  if (availabilityDate != null)
                    TextButton(
                      onPressed: saving ? null : onClearAvailability,
                      child: Text(isAr ? 'مسح' : 'Clear'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isAr
                    ? 'اليوم أو مضى: متاح للمسوقين بعد الموافقة. مستقبلي: يُفضّل عرضه بعد ذلك التاريخ.'
                    : 'Past/today: available to marketers after approval. Future: prefer showing after that date.',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// السؤال الأول: «هل الإجمالي شامل ضريبة القيمة المضافة 5%؟»
class _VatInclusionQuestion extends StatelessWidget {
  final bool isAr;
  final bool saving;
  final bool? value;
  final ValueChanged<bool> onChanged;

  const _VatInclusionQuestion({
    required this.isAr,
    required this.saving,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final missing = value == null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: missing
            ? cs.errorContainer.withValues(alpha: 0.18)
            : cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: missing
              ? cs.error.withValues(alpha: 0.45)
              : cs.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isAr
                      ? 'هل الإجمالي شامل ضريبة القيمة المضافة 5%؟'
                      : 'Does the total include 5% VAT?',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              StableSelectChip(
                label: isAr ? 'نعم — شامل' : 'Yes — included',
                exclusive: true,
                showLeadingCheck: false,
                selected: value == true,
                enabled: !saving,
                onSelected: (_) => onChanged(true),
              ),
              StableSelectChip(
                label: isAr ? 'لا — يضاف 5%' : 'No — add 5%',
                exclusive: true,
                showLeadingCheck: false,
                selected: value == false,
                enabled: !saving,
                onSelected: (_) => onChanged(false),
              ),
            ],
          ),
          if (missing)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                isAr
                    ? 'الإجابة مطلوبة قبل النشر لضمان وضوح الفاتورة.'
                    : 'Answer required before publishing for invoice clarity.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: cs.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// السؤال الثاني: «هل إجمالي السعر يحوي عمولة التسويق 2.5% أم مبلغ مقطوع؟»
class _CommissionKindQuestion extends StatelessWidget {
  final bool isAr;
  final bool saving;
  final String value; // none | percent | fixed
  final ValueChanged<String> onChanged;
  final TextEditingController fixedAmountCtrl;
  final String currencyCode;

  const _CommissionKindQuestion({
    required this.isAr,
    required this.saving,
    required this.value,
    required this.onChanged,
    required this.fixedAmountCtrl,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.percent, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isAr
                      ? 'هل إجمالي السعر يحوي عمولة التسويق العقاري؟'
                      : 'Does the total include marketing commission?',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              StableSelectChip(
                label: isAr ? 'لا توجد عمولة' : 'No commission',
                exclusive: true,
                showLeadingCheck: false,
                selected: value == 'none',
                enabled: !saving,
                onSelected: (_) => onChanged('none'),
              ),
              StableSelectChip(
                label: isAr ? 'عمولة 2.5%' : '2.5% commission',
                exclusive: true,
                showLeadingCheck: false,
                selected: value == 'percent',
                enabled: !saving,
                onSelected: (_) => onChanged('percent'),
              ),
              StableSelectChip(
                label: isAr ? 'مبلغ مقطوع' : 'Fixed amount',
                exclusive: true,
                showLeadingCheck: false,
                selected: value == 'fixed',
                enabled: !saving,
                onSelected: (_) => onChanged('fixed'),
              ),
            ],
          ),
          if (value == 'fixed') ...[
            const SizedBox(height: 8),
            AqarTextFormField(
              controller: fixedAmountCtrl,
              enabled: !saving,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: latinDecimalNumberFormatters(),
              decoration: InputDecoration(
                labelText: isAr
                    ? 'مبلغ العمولة المقطوع ($currencyCode)'
                    : 'Fixed commission amount ($currencyCode)',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                if (value != 'fixed') return null;
                final s = _AddPropertyPageState.normalizeNumbers(v ?? '')
                    .trim();
                if (s.isEmpty) return isAr ? 'مطلوب' : 'Required';
                final n = double.tryParse(s);
                if (n == null || n <= 0) {
                  return isAr ? 'أدخل مبلغاً موجباً' : 'Enter a positive amount';
                }
                return null;
              },
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              isAr
                  ? 'عمولة التسويق العقاري المعتمدة عادةً 2.5% من السعر الأساسي وتُحسب بعد ضبط ضريبة القيمة المضافة.'
                  : 'Standard real-estate marketing commission is 2.5% of the base price, computed after adjusting VAT.',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
