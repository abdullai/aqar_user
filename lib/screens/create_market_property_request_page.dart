// ignore_for_file: unused_element, unused_element_parameter, unused_field, unused_local_variable

import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:aqar_user/core/gestures/app_keyboard_popups.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/branding/app_branding.dart';
import '../core/haptics/app_haptics.dart';
import '../core/input/input_normalizers.dart' as input_norm;
import '../core/permissions/runtime_permission_helper.dart';
import '../core/input/saudi_input_formatters.dart';
import '../core/listing/property_type_catalog.dart';
import '../core/listing/post_publish_nav_result.dart';
import '../core/listing/property_listing_display.dart';
import '../core/utils/app_money.dart';
import '../core/payment/platform_fee_catalog.dart';
import '../core/utils/display_ids.dart';
import '../core/profile/publisher_identity_prefs.dart';
import '../widgets/publisher_identity_options_card.dart';
import '../l10n/app_localizations.dart';
import '../models/market_property_request_row.dart';
import '../models/market_property_request_priority.dart';
import '../models/saudi_location.dart';
import '../services/saudi_location_hierarchy.dart';
import '../core/market/market_request_rent_schedule.dart';
import '../services/location_hierarchy_service.dart';
import '../widgets/deed_date_calendar_dialog.dart';
import '../widgets/equal_option_tile_grid.dart';
import '../widgets/rent_term_schedule_fields.dart';
import '../widgets/saudi_riyal_symbol_icon.dart';
import '../core/utils/date_helper.dart';
import '../core/subscription/app_subscription_gate.dart';
import '../core/subscription/subscription_gate_helper.dart';
import '../services/instant_market_request_payment_service.dart';
import '../services/saudi_locations_service.dart';
import '../core/forms/market_request_form_draft.dart';
import '../core/forms/wizard_form_draft.dart';
import '../core/forms/wizard_step_navigation.dart';
import '../core/forms/active_form_guard.dart';
import '../core/forms/publish_content_fingerprint_store.dart';
import '../core/session/app_session.dart';
import '../widgets/form_exit_confirm_dialog.dart';
import '../widgets/adaptive_post_publish_dialog.dart';
import '../widgets/terms_acceptance_checkbox.dart';
import 'platform_policies_screen.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/budget_text_field.dart';
import '../widgets/searchable_select_field.dart';
import '../widgets/smart_count_field.dart';
import '../core/navigation/post_auth_navigation.dart';
import '../core/navigation/safe_overlay_pop.dart';
import '../core/gestures/app_keyboard_inset.dart';
import '../widgets/composer_step_constellation.dart';
import '../main.dart' show suspendAutoLock;
import 'map_picker_page.dart';

enum _CoverPickSource { gallery, camera, files }

/// نموذج خفيف لنشر «طلب عقاري» (منفصل عن شاشة إضافة الإعلان).
class CreateMarketPropertyRequestPage extends StatefulWidget {
  final String userId;
  final String lang;
  final MarketPropertyRequestRow? initialRequest;

  /// عند `true`: يخفي سهم الرجوع الداخلي — لوحة الداشبورد تعرضه.
  final bool embedAppBar;

  const CreateMarketPropertyRequestPage({
    super.key,
    required this.userId,
    required this.lang,
    this.initialRequest,
    this.embedAppBar = false,
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
  final _manualRegionCtrl = TextEditingController();
  final _manualGovCtrl = TextEditingController();
  final _manualCityCtrl = TextEditingController();
  bool _manualLocation = false;

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

  /// مدة الإيجار عند اختيار «إيجار» — فارغة حتى يختار المستخدم.
  String _rentTerm = '';
  int _rentDays = 1;
  int _rentWeeks = 1;
  int _rentMonths = 1;
  int _rentYears = 1;
  DateTime? _rentStart;
  bool? _furnishedWanted;
  List<String> _districtOptions = const [];
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
    'wifi': false,
    'maid_room': false,
    'driver_room': false,
    'storage': false,
    'roof': false,
    'kitchen': false,
    'majlis': false,
    'yard': false,
  };
  bool? _preferNew;
  bool _locationIsApproximate = false;
  PublicNameSource _pubNameSource = PublicNameSource.official;
  PublicPhoneSource _pubPhoneSource = PublicPhoneSource.hidden;
  bool _publishPresenceOnCards = true;
  bool _showRequesterNameOnCards = false;
  String _officialNameCached = '';
  String _displayAliasCached = '';
  String _primaryPhoneCached = '';
  String _secondaryPhoneCached = '';
  bool _saving = false;
  // — قفل نشر الطلب: يبقى مرفوعاً حتى انتهاء حوار النجاح ورمز الطلب،
  //   ليمنع إرسال نسخ متعددة عند الضغط المتكرر.
  bool _publishLock = false;
  bool _usedDefaultCover = false;
  bool _locationsLoading = true;
  Uint8List? _coverBytes;
  String? _coverFileName;

  int _step = 0;
  static const int _stepCount = 4;
  bool _pickingCover = false;
  String? _instantCreditId;
  String? _instantBillingId;
  bool _loadingInstantCredit = false;
  bool _termsAccepted = false;
  static const _draftNamespace = 'market_property_request';
  AppSession? _appSession;

  static const List<MarketPropertyRequestPriority> _priorityChoices = [
    MarketPropertyRequestPriority.standard,
    MarketPropertyRequestPriority.immediate,
  ];

  final ScrollController _stepScrollCtrl = ScrollController();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _publicNameFocus = FocusNode();

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
    ActiveFormGuard.instance.unregister('market_property_request');
    _appSession?.removeListener(_onConnectivityForDraft);
    _stepScrollCtrl.dispose();
    _titleFocus.dispose();
    _publicNameFocus.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _budgetMinCtrl.dispose();
    _budgetMaxCtrl.dispose();
    _areaMinCtrl.dispose();
    _publicNameCtrl.dispose();
    _districtsCtrl.dispose();
    _manualRegionCtrl.dispose();
    _manualGovCtrl.dispose();
    _manualCityCtrl.dispose();
    super.dispose();
  }

  bool _hasUnsavedWizardInput() {
    if (_coverBytes != null && _coverBytes!.isNotEmpty) return true;
    return _titleCtrl.text.trim().isNotEmpty ||
        _descCtrl.text.trim().isNotEmpty ||
        _budgetMinCtrl.text.trim().isNotEmpty ||
        _budgetMaxCtrl.text.trim().isNotEmpty ||
        _areaMinCtrl.text.trim().isNotEmpty ||
        _districtsCtrl.text.trim().isNotEmpty ||
        _publicNameCtrl.text.trim().isNotEmpty;
  }

  void _scrollStepToTop() {
    WizardStepNavigation.scrollToTop(_stepScrollCtrl);
  }

  void _goNextStep() {
    if (!_validateStepBeforeLeave(_step)) {
      if (_step == 0 && _titleCtrl.text.trim().isEmpty) {
        _titleFocus.requestFocus();
      }
      return;
    }
    if (_step >= _stepCount - 1) return;
    setState(() {
      _syncComposedTitle();
      _step++;
    });
    if (!_isEditing) {
      unawaited(_persistDraft(showSnack: false));
    }
    _scrollStepToTop();
  }

  void _goPrevStep() {
    if (_step <= 0) return;
    setState(() => _step--);
    if (!_isEditing) {
      unawaited(_persistDraft(showSnack: false));
    }
    _scrollStepToTop();
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
    unawaited(_loadAvailableInstantCredit());
    if (!_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_restoreDraftIfAny());
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _appSession = context.read<AppSession>();
      _appSession?.addListener(_onConnectivityForDraft);
      ActiveFormGuard.instance.register(
        ActiveFormGuardHandle(
          id: 'market_property_request',
          hasUnsavedInput: () => !_isEditing && _hasUnsavedWizardInput(),
          isPublishing: () => _saving || _publishLock,
          onSaveDraft: () => _persistDraft(showSnack: false),
          onDiscard: _clearDraftAndForm,
          leaveTitleAr: 'هل تريد إغلاق الطلب؟',
          leaveTitleEn: 'Leave this request?',
        ),
      );
      unawaited(_ensureSubscriptionForCreatePage());
    });
    if (_requestPriority == MarketPropertyRequestPriority.flexible ||
        _requestPriority == MarketPropertyRequestPriority.priority ||
        _requestPriority == MarketPropertyRequestPriority.urgent) {
      _requestPriority = MarketPropertyRequestPriority.standard;
    }
  }

  void _onConnectivityForDraft() {
    if (_isEditing || !_hasUnsavedWizardInput()) return;
    if (_appSession?.hasInternet == false) {
      unawaited(_persistDraft(showSnack: false));
    }
  }

  Map<String, dynamic> _snapshotDraft() {
    return MarketRequestFormDraft.serialize(
      step: _step,
      title: _titleCtrl.text,
      desc: _descCtrl.text,
      budgetMin: _budgetMinCtrl.text,
      budgetMax: _budgetMaxCtrl.text,
      areaMin: _areaMinCtrl.text,
      publicName: _publicNameCtrl.text,
      districts: _districtsCtrl.text,
      purchase: _purchase,
      requestPriority: _requestPriority.name,
      typeKey: _typeKey,
      typeGroupId: _typeGroupId,
      cityKey: _cityKey,
      selectedRegion: _selectedRegion,
      selectedGovernorate: _selectedGovernorate,
      selectedLat: _selectedLat,
      selectedLng: _selectedLng,
      rentTerm: _rentTerm,
      bedrooms: _bedrooms,
      bathrooms: _bathrooms,
      amenityToggles: Map<String, bool>.from(_requestAmenityToggles),
      preferNew: _preferNew,
      furnishedWanted: _furnishedWanted,
      rentDays: _rentDays,
      rentWeeks: _rentWeeks,
      rentMonths: _rentMonths,
      rentYears: _rentYears,
      rentStartIso: _rentStart?.toIso8601String(),
    );
  }

  void _applyDraft(Map<String, dynamic> d) {
    _step = (d['step'] as num?)?.toInt().clamp(0, _stepCount - 1) ?? 0;
    _titleCtrl.text = '${d['title'] ?? ''}';
    _descCtrl.text = '${d['desc'] ?? ''}';
    _budgetMinCtrl.text = '${d['budget_min'] ?? ''}';
    _budgetMaxCtrl.text = '${d['budget_max'] ?? ''}';
    _areaMinCtrl.text = '${d['area_min'] ?? ''}';
    _publicNameCtrl.text = '${d['public_name'] ?? ''}';
    _districtsCtrl.text = '${d['districts'] ?? ''}';
    _purchase = d['purchase'] == true;
    final pr = '${d['request_priority'] ?? ''}';
    try {
      _requestPriority = MarketPropertyRequestPriority.values.byName(pr);
    } catch (_) {
      _requestPriority = MarketPropertyRequestPriority.standard;
    }
    _typeKey = '${d['type_key'] ?? _typeKey}';
    _typeGroupId = '${d['type_group_id'] ?? _typeGroupId}';
    _cityKey = '${d['city_key'] ?? ''}';
    _selectedRegion = d['selected_region']?.toString();
    _selectedGovernorate = d['selected_governorate']?.toString();
    _selectedLat = (d['selected_lat'] as num?)?.toDouble();
    _selectedLng = (d['selected_lng'] as num?)?.toDouble();
    _rentTerm = '${d['rent_term'] ?? ''}';
    _rentDays = (d['rent_days'] as num?)?.toInt().clamp(1, 6) ?? 1;
    _rentWeeks = (d['rent_weeks'] as num?)?.toInt().clamp(1, 3) ?? 1;
    _rentMonths = (d['rent_months'] as num?)?.toInt().clamp(1, 12) ?? 1;
    _rentYears = (d['rent_years'] as num?)?.toInt().clamp(1, 20) ?? 1;
    final rs = '${d['rent_start'] ?? ''}';
    _rentStart = DateTime.tryParse(rs);
    _furnishedWanted = _triChoiceFromDraft(d, 'furnished');
    _bedrooms = (d['bedrooms'] as num?)?.toInt();
    _bathrooms = (d['bathrooms'] as num?)?.toInt();
    for (final k in _requestAmenityToggles.keys) {
      _requestAmenityToggles[k] = false;
    }
    _applyAmenitySelections(d['amenities']);
    _preferNew = _triChoiceFromDraft(d, 'prefer_new');
  }

  /// مسودات قديمة كانت تخزّن `false` كقيمة افتراضية — لا نضع صح مسبقاً.
  bool? _triChoiceFromDraft(Map<String, dynamic> d, String key) {
    if (d['choice_tristate'] == true) {
      final v = d[key];
      return v is bool ? v : null;
    }
    return d[key] == true ? true : null;
  }

  Future<void> _restoreDraftIfAny() async {
    if (_isEditing || widget.initialRequest != null) return;
    final draft = await WizardFormDraft.load(
      namespace: _draftNamespace,
      userId: widget.userId,
    );
    if (!mounted || draft == null) return;
    if (_hasUnsavedWizardInput()) return;
    setState(() => _applyDraft(draft));
    _scrollStepToTop();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(_isAr
              ? 'تم استرجاع مسودة الطلب — أكمل من حيث توقفت.'
              : 'Draft restored — continue where you left off.'),
        ),
      );
    }
  }

  Future<void> _persistDraft({bool showSnack = true}) async {
    await WizardFormDraft.save(
      namespace: _draftNamespace,
      userId: widget.userId,
      data: _snapshotDraft(),
    );
    if (showSnack && mounted) {
      final l10n = AppLocalizations.of(context);
      showFormExitNotice(
        context,
        l10n?.formExitDraftSaved ??
            (_isAr
                ? 'حُفظت البيانات التي أدخلتها كمسودة على هذا الجهاز. يمكنك العودة لآخر حقل وصلت إليه وإكمال الإدخال. المسودة لا تُرسل إلى قاعدة البيانات، وتُحذف تلقائياً عند تسجيل الخروج.'
                : 'Your entries were saved as a draft on this device. You can return to the last field you filled and continue. This draft is not stored in the database and is removed when you sign out.'),
      );
    }
  }

  Future<void> _clearDraftAndForm() async {
    _titleCtrl.clear();
    _descCtrl.clear();
    _budgetMinCtrl.clear();
    _budgetMaxCtrl.clear();
    _areaMinCtrl.clear();
    _publicNameCtrl.clear();
    _districtsCtrl.clear();
    _coverBytes = null;
    _coverFileName = null;
    _step = 0;
    _purchase = true;
    _requestPriority = MarketPropertyRequestPriority.standard;
    _typeKey = 'villa';
    _typeGroupId = PropertyTypeCatalog.groupIdForCode(_typeKey);
    _cityKey = '';
    _selectedRegion = null;
    _selectedGovernorate = null;
    _selectedLat = null;
    _selectedLng = null;
    _locationIsApproximate = false;
    _rentTerm = '';
    _rentDays = 1;
    _rentWeeks = 1;
    _rentMonths = 1;
    _rentYears = 1;
    _rentStart = null;
    _furnishedWanted = null;
    _bedrooms = null;
    _bathrooms = null;
    _preferNew = null;
    _termsAccepted = false;
    for (final k in _requestAmenityToggles.keys) {
      _requestAmenityToggles[k] = false;
    }
    if (mounted) setState(() {});
    unawaited(WizardFormDraft.clear(
      namespace: _draftNamespace,
      userId: widget.userId,
    ));
  }

  Future<void> _onComposerClosePressed() async {
    if (_saving || _publishLock) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(_isAr
              ? 'جاري نشر الطلب… يرجى الانتظار حتى ظهور رقم الطلب.'
              : 'Publishing request… please wait for the confirmation.'),
        ),
      );
      return;
    }
    if (_isEditing || !_hasUnsavedWizardInput()) {
      SafeOverlayPop.pop(context);
      return;
    }
    await _handleFormExitFromPop();
  }

  Future<void> _handleFormExitFromPop([dynamic result]) async {
    final choice = await showFormExitConfirmDialog(
      context: context,
      isAr: _isAr,
      title: _isAr ? 'هل تريد إغلاق الطلب؟' : 'Leave this request?',
    );
    if (!mounted || choice == null || choice == FormExitChoice.keepEditing) {
      return;
    }
    if (choice == FormExitChoice.saveDraft) {
      await _persistDraft();
      return;
    }
    await _clearDraftAndForm();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    showFormExitNotice(
      context,
      l10n?.formExitCleared ??
          (_isAr
              ? 'مُسحت كل البيانات التي أدخلتها في الحقول. لم تُحفظ كمسودة.'
              : 'All entered data was cleared. Nothing was saved as a draft.'),
    );
    SafeOverlayPop.pop(context, 'closed');
  }

  Future<void> _ensureSubscriptionForCreatePage() async {
    if (!mounted) return;
    await SubscriptionGateHelper.ensure(
      context,
      isAr: _isAr,
      action: SubscriptionGateAction.addMarketPropertyRequest,
      onGoSubscribe: () {
        if (!mounted) return;
        Navigator.of(context).pop('subscribe');
      },
    );
  }

  Future<void> _loadAvailableInstantCredit() async {
    setState(() => _loadingInstantCredit = true);
    try {
      final res = await InstantMarketRequestPaymentService(_sb)
          .getAvailableCredit();
      if (!mounted) return;
      if (res['ok'] == true && res['has_credit'] == true) {
        setState(() {
          _instantCreditId = res['credit_id']?.toString();
          _instantBillingId = res['billing_transaction_id']?.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _loadingInstantCredit = false);
    }
  }

  Future<void> _payForInstantPriority() async {
    final paid = await SubscriptionGateHelper.payInstantMarketRequest(
      context: context,
      isAr: _isAr,
      lang: widget.lang,
    );
    if (!mounted || paid == null || !paid.ok) {
      if (mounted) {
        final err = paid?.error?.trim() ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isAr
                      ? (err.isEmpty
                          ? PlatformFeeCatalog.of(context).instantPayIncomplete(isAr: true)
                          : 'لم يُكتمل الدفع: $err')
                      : (err.isEmpty
                          ? PlatformFeeCatalog.of(context).instantPayIncomplete(isAr: false)
                          : 'Payment not completed: $err'),
            ),
          ),
        );
      }
      return;
    }
    setState(() {
      _instantCreditId = paid.creditId;
      _instantBillingId = paid.billingTransactionId;
      _requestPriority = MarketPropertyRequestPriority.immediate;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isAr
              ? 'تم الدفع — يمكنك إكمال الطلب الفوري الآن.'
              : 'Payment complete — you can finish your instant request.',
        ),
      ),
    );
  }

  Future<void> _cancelUnusedInstantCredit() async {
    final cid = _instantCreditId?.trim() ?? '';
    if (cid.isEmpty) return;
    final confirm = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isAr ? 'إلغاء رصيد الطلب الفوري' : 'Cancel instant credit'),
        content: Text(
          PlatformFeeCatalog.of(context).unusedPaymentReversal(isAr: _isAr),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'تراجع' : 'Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'إلغاء الطلب واسترجاع المبلغ' : 'Cancel & refund'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final res = await InstantMarketRequestPaymentService(_sb)
        .refundUnusedCredit(cid);
    if (!mounted) return;
    if (res['ok'] == true) {
      setState(() {
        _instantCreditId = null;
        _instantBillingId = null;
        if (_requestPriority == MarketPropertyRequestPriority.immediate) {
          _requestPriority = MarketPropertyRequestPriority.standard;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res['message_ar']?.toString() ??
                (_isAr ? 'تم الاسترجاع.' : 'Refunded.'),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res['message_ar']?.toString() ??
                res['error']?.toString() ??
                (_isAr ? 'تعذّر الاسترجاع.' : 'Refund failed.'),
          ),
        ),
      );
    }
  }

  void _showInstantPriorityInfo() {
    showAppDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(PlatformFeeCatalog.of(ctx, listen: true).instantTitle(isAr: _isAr)),
        content: SingleChildScrollView(
          child: Text(
            _isAr
                ? '• يظهر طلبك في أعلى الرئيسية مع تمييز بصري.\n'
                  '• يلزم دفع ${PlatformFeeCatalog.of(ctx).instantPhrase(isAr: true)} لكل طلب فوري (مرة واحدة).\n'
                  '• إذا دفعت ولم تنشر الطلب، يبقى الرصيد لطلب فوري آخر.\n'
                  '• زر «إلغاء الطلب» يظهر فقط قبل الاستفادة — لاسترجاع المبلغ.\n'
                  '• بعد النشر لا يمكن الاسترجاع — الدفع مرتبط بالطلب المنشور.\n'
                  '• الفاتورة والإيصال متاحان بعد الدفع (طباعة/تصدير).'
                : '• Your request stays at the top of home with a visual highlight.\n'
                  '• ${PlatformFeeCatalog.of(ctx).instantPhrase(isAr: false)} one-time payment per instant request.\n'
                  '• If you pay but do not publish, credit applies to another instant request.\n'
                  '• «Cancel request» appears only before use — to refund.\n'
                  '• After publishing, no refund — payment is tied to the live request.\n'
                  '• Invoice/receipt available after payment (print/export).',
          ),
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

  Future<void> _onPriorityChanged(MarketPropertyRequestPriority v) async {
    if (v == MarketPropertyRequestPriority.immediate) {
      if ((_instantCreditId ?? '').isEmpty) {
        final go = await showAppDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(_isAr ? 'دفع الطلب الفوري' : 'Pay for instant request'),
            content: Text(
              _isAr
                  ? 'خيار فوري يتطلب دفعاً. تُفتح صفحة الدفع ثم تعود لإكمال الطلب.'
                  : 'Instant requires payment. You will pay then return to finish.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(_isAr ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(_isAr ? 'متابعة الدفع' : 'Continue to pay'),
              ),
            ],
          ),
        );
        if (go != true || !mounted) {
          if (mounted) {
            setState(() {
              _requestPriority = MarketPropertyRequestPriority.standard;
            });
          }
          return;
        }
        await _payForInstantPriority();
        if (!mounted) return;
        if ((_instantCreditId ?? '').isEmpty) {
          setState(() {
            _requestPriority = MarketPropertyRequestPriority.standard;
          });
        }
        return;
      }
      setState(() => _requestPriority = v);
      _showSnack(
        _isAr
            ? 'سيُستخدم رصيد فوري سابق لهذا الطلب.'
            : 'Existing instant credit will be used for this request.',
      );
      return;
    }
    setState(() => _requestPriority = v);
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
    _showRequesterNameOnCards = r.showRequesterName;
    _publishPresenceOnCards = r.publishPresenceOnCards;
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
    _locationIsApproximate = details['location_is_approximate'] == true ||
        (nestedLocation is Map && nestedLocation['approximate'] == true);
    _bedrooms = _intFromAny(details['bedrooms']);
    _bathrooms = _intFromAny(details['bathrooms']);
    for (final key in _requestAmenityToggles.keys) {
      _requestAmenityToggles[key] = false;
    }
    _applyAmenitySelections(details['amenities']);
    _furnishedWanted =
        details.containsKey('furnished') && details['furnished'] is bool
            ? details['furnished'] as bool
            : null;
    _preferNew =
        details.containsKey('prefer_new') && details['prefer_new'] is bool
            ? details['prefer_new'] as bool
            : null;
  }

  void _applyAmenitySelections(dynamic raw) {
    if (raw is Map) {
      for (final e in raw.entries) {
        final k = e.key.toString();
        if (_requestAmenityToggles.containsKey(k) && _amenityFlagOn(e.value)) {
          _requestAmenityToggles[k] = true;
        }
      }
      return;
    }
    if (raw is List) {
      // قائمة المفاتيح المختارة فقط — لا نعتبر كل مفاتيح الكتالوج محددة.
      for (final item in raw) {
        if (item is Map) {
          for (final e in item.entries) {
            final k = e.key.toString();
            if (_requestAmenityToggles.containsKey(k) &&
                _amenityFlagOn(e.value)) {
              _requestAmenityToggles[k] = true;
            }
          }
          continue;
        }
        final k = item.toString().trim();
        if (_requestAmenityToggles.containsKey(k)) {
          _requestAmenityToggles[k] = true;
        }
      }
    }
  }

  static bool _amenityFlagOn(dynamic value) {
    if (value == true || value == 1) return true;
    if (value is String) {
      final s = value.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
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
        _manualLocation = all.isEmpty;
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
          _manualLocation = true;
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

  bool _wantsResidentialDetailFields() =>
      PropertyTypeCatalog.showsResidentialRoomBedCountsEffective(_typeKey);

  bool _wantsAmenityFields() => _requestAmenityToggles.keys.any(
        (k) => PropertyTypeCatalog.amenityKeyRelevantForType(_typeKey, k),
      );

  DateTime? get _rentEndComputed {
    if (_purchase || _rentTerm.isEmpty || _rentStart == null) return null;
    return MarketRequestRentSchedule.endOf(
      term: _rentTerm,
      start: _rentStart!,
      days: _rentDays,
      weeks: _rentWeeks,
      months: _rentMonths,
      years: _rentYears,
    );
  }

  String _fmtG(DateTime d) => DateHelper.fmtCivilDate(d, isAr: _isAr);

  Future<void> _pickRentStart() async {
    final picked = await showDeedDateCalendarDialog(
      context: context,
      isAr: _isAr,
      initialDate: _rentStart ?? DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _rentStart = MarketRequestRentSchedule.dateOnly(picked));
  }

  void _applyRentTerm(String term) {
    setState(() {
      _rentTerm = term;
      if (term == 'monthly' && _rentMonths >= 12) {
        _rentTerm = 'yearly';
        _rentYears = 1;
        _rentMonths = 1;
      }
    });
  }

  void _setRentMonths(int n) {
    setState(() {
      if (n >= 12) {
        _rentTerm = 'yearly';
        _rentYears = 1;
        _rentMonths = 12;
      } else {
        _rentMonths = n.clamp(1, 11);
        _rentTerm = 'monthly';
      }
    });
  }

  String _composedRequestTitle() {
    final typeLabel = PropertyTypeCatalog.label(_typeKey, _isAr);
    final purposeBit = _purchase
        ? (_isAr ? 'للشراء' : 'to buy')
        : switch (_rentTerm) {
            'daily' => _isAr ? 'إيجار يومي' : 'daily rent',
            'weekly' => _isAr ? 'إيجار أسبوعي' : 'weekly rent',
            'monthly' => _isAr ? 'إيجار شهري' : 'monthly rent',
            'yearly' => _isAr ? 'إيجار سنوي' : 'yearly rent',
            _ => _isAr ? 'للإيجار' : 'to rent',
          };
    final city = _cityForSubmit().trim();
    final districts = _districtsCtrl.text.trim();
    final suggested = PropertyListingDisplay.composeListingHeadline(
      typeLabel: typeLabel,
      purposeBit: purposeBit,
      city: city,
      district: districts.isNotEmpty ? districts : null,
      isAr: _isAr,
      asRequest: true,
    );
    return suggested.trim().isEmpty
        ? (_isAr ? 'طلب عقاري' : 'Property request')
        : suggested.trim();
  }

  void _syncComposedTitle() {
    _titleCtrl.text = _composedRequestTitle();
  }

  void _fillSmartDetails() {
    final parts = <String>[];
    parts.add(_composedRequestTitle());
    if (!_purchase && _rentTerm.isNotEmpty) {
      final start = _rentStart;
      final end = _rentEndComputed;
      if (start != null && end != null) {
        parts.add(_isAr
            ? 'المدة: ${_fmtG(start)} — ${_fmtG(end)}'
            : 'Period: ${_fmtG(start)} — ${_fmtG(end)}');
      }
    }
    final min = _parseMoney(_budgetMinCtrl.text);
    final max = _parseMoney(_budgetMaxCtrl.text);
    if (min != null || max != null) {
      parts.add(_isAr
          ? 'المبلغ المحدد: ${_requestBudgetLabel() ?? ''}'
          : 'Budget: ${_requestBudgetLabel() ?? ''}');
    }
    if (_areaMinCtrl.text.trim().isNotEmpty) {
      parts.add(_isAr
          ? 'مساحة لا تقل عن ${_areaMinCtrl.text.trim()} م²'
          : 'Min area ${_areaMinCtrl.text.trim()} m²');
    }
    if (_bedrooms != null) {
      parts.add(_isAr ? 'غرف نوم: $_bedrooms' : 'Bedrooms: $_bedrooms');
    }
    if (_bathrooms != null) {
      parts.add(_isAr ? 'دورات مياه: $_bathrooms' : 'Baths: $_bathrooms');
    }
    if (_furnishedWanted == true) {
      parts.add(_isAr ? 'مفروش' : 'Furnished');
    } else if (_furnishedWanted == false) {
      parts.add(_isAr ? 'غير مفروش' : 'Unfurnished');
    }
    if (_preferNew == true) {
      parts.add(_isAr ? 'يفضّل جديد' : 'Prefer new');
    } else if (_preferNew == false) {
      parts.add(_isAr ? 'لا يشترط الجديد' : 'New not required');
    }
    setState(() => _descCtrl.text = parts.join(_isAr ? ' · ' : ' · '));
  }

  Future<void> _refreshDistricts() async {
    final ar = _cityForSubmit();
    final L = _locationForCityKey(_cityKey);
    final en = L?.cityEn ?? ar;
    final svc = LocationHierarchyService.instance;
    var list = await svc.districtsIn(city: ar);
    if (list.isEmpty && en != ar) list = await svc.districtsIn(city: en);
    if (!mounted) return;
    setState(() => _districtOptions = list);
  }

  String get _coordsCombined {
    final lat = _selectedLat;
    final lng = _selectedLng;
    if (lat == null || lng == null) return '';
    return '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
  }

  Future<void> _copyCoords() async {
    final s = _coordsCombined;
    if (s.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: s));
    _showSnack(_isAr ? 'نُسخت الإحداثيات' : 'Coordinates copied');
  }

  Widget _instantFeeChip(ColorScheme cs) {
    final cat = PlatformFeeCatalog.of(context, listen: true);
    final n = cat.numberText(
      PlatformFeeCatalog.instantMarketRequest,
      isAr: _isAr,
    );
    if (n.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isAr)
          SaudiRiyalSymbolIcon(size: 14, color: cs.primary)
        else
          Text(
            AppMoney.sarUiSuffix(isAr: false),
            style: TextStyle(
              color: cs.primary,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              fontFamily: 'Cairo',
            ),
          ),
        const SizedBox(width: 4),
        Text(
          n,
          style: TextStyle(
            color: cs.primary,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    );
  }

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
      out['rent_days'] = _rentDays;
      out['rent_weeks'] = _rentWeeks;
      out['rent_months'] = _rentMonths;
      out['rent_years'] = _rentYears;
      if (_rentStart != null) {
        out['rent_start'] = _rentStart!.toIso8601String();
        final end = _rentEndComputed;
        if (end != null) out['rent_end'] = end.toIso8601String();
      }
    }
    if (_furnishedWanted != null) out['furnished'] = _furnishedWanted;
    if (_preferNew != null) out['prefer_new'] = _preferNew;
    final region = (_selectedRegion ?? '').trim();
    if (region.isNotEmpty) out['region'] = region;
    final gov = (_selectedGovernorate ?? '').trim();
    if (gov.isNotEmpty) out['governorate'] = gov;
    if (_selectedLat != null && _selectedLng != null) {
      out['lat'] = _selectedLat;
      out['lng'] = _selectedLng;
      out['location_is_approximate'] = _locationIsApproximate;
      out['location'] = {
        'lat': _selectedLat,
        'lng': _selectedLng,
        'approximate': _locationIsApproximate,
        'source': 'map_picker',
      };
    } else {
      final cityLoc = _locationForCityKey(_cityKey);
      if (cityLoc != null &&
          !(cityLoc.lat.abs() < 1e-5 && cityLoc.lng.abs() < 1e-5)) {
        out['lat'] = cityLoc.lat;
        out['lng'] = cityLoc.lng;
        out['location_is_approximate'] = true;
        out['location'] = {
          'lat': cityLoc.lat,
          'lng': cityLoc.lng,
          'approximate': true,
          'source': 'city_centroid',
        };
      }
    }
    if (_wantsResidentialDetailFields()) {
      if (_bedrooms != null) out['bedrooms'] = _bedrooms;
      if (_bathrooms != null) out['bathrooms'] = _bathrooms;
    }
    if (_wantsAmenityFields()) {
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
    final raw = _hierarchy!.governoratesByRegion[r] ?? const [];
    final mains = raw.where((g) => g.trim() != r.trim()).toList();
    return mains.isNotEmpty ? mains : raw;
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

  void _applyManualLocationFields() {
    final r = _manualRegionCtrl.text.trim();
    final g = _manualGovCtrl.text.trim();
    final c = _manualCityCtrl.text.trim();
    _selectedRegion = r.isEmpty ? _selectedRegion : r;
    _selectedGovernorate = g.isEmpty ? _selectedGovernorate : g;
    if (c.isNotEmpty) _cityKey = c;
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
      unawaited(_refreshDistricts());
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
      Map<String, dynamic>? row;
      try {
        row = await _sb
            .from('users_profiles')
            .select(
              'first_name_ar,second_name_ar,third_name_ar,fourth_name_ar,'
              'first_name_en,second_name_en,third_name_en,fourth_name_en,'
              'full_name_ar,full_name_en,full_name,office_name,username,avatar_url,'
              'display_name,public_name_source,phone,secondary_phone,'
              'public_phone_source,publish_presence_on_cards,account_type',
            )
            .eq('user_id', widget.userId)
            .maybeSingle();
      } catch (_) {
        row = await _sb
            .from('users_profiles')
            .select(
              'first_name_ar,second_name_ar,third_name_ar,fourth_name_ar,'
              'first_name_en,second_name_en,third_name_en,fourth_name_en,'
              'full_name_ar,full_name_en,full_name,username,avatar_url',
            )
            .eq('user_id', widget.userId)
            .maybeSingle();
      }
      if (!mounted || row == null) return;
      _profileRow = Map<String, dynamic>.from(row);
      await PublisherIdentityPrefs.instance.reload(profileRow: _profileRow);
      final id = PublisherIdentityPrefs.instance;
      final av = (_profileRow!['avatar_url'] ?? '').toString().trim();
      final d = id.resolvedPublicName(isAr: _isAr);
      setState(() {
        _profileAvatarUrl = av;
        _pubNameSource = id.nameSource;
        _pubPhoneSource = PublicPhoneSource.hidden;
        _publishPresenceOnCards = true;
        _officialNameCached = id.officialName(isAr: _isAr);
        _displayAliasCached = id.aliasName(isAr: _isAr);
        _primaryPhoneCached = id.primaryPhone;
        _secondaryPhoneCached = id.secondaryPhone;
        if (!_isEditing || _publicNameCtrl.text.trim().isEmpty) {
          if (d.isNotEmpty) _publicNameCtrl.text = d;
        }
      });
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
    final res = await Navigator.of(context, rootNavigator: true)
        .push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        settings: const RouteSettings(name: '/map-picker'),
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
    final approx = res['approximate'] == true;
    final hit = await SaudiLocationsService.instance.findNearest(lat, lng);
    if (!mounted) return;
    if (hit == null) {
      setState(() {
        _selectedLat = lat;
        _selectedLng = lng;
        _locationIsApproximate = approx;
        _manualLocation = true;
      });
      return;
    }
    final reg = _isAr ? hit.regionAr.trim() : hit.regionEn.trim();
    final rawG = _isAr ? hit.governorateAr?.trim() : hit.governorateEn?.trim();
    final gov = (rawG != null && rawG.isNotEmpty) ? rawG : reg;
    setState(() {
      _cityKey = hit.cityEn;
      _selectedRegion = reg.isEmpty ? null : reg;
      _selectedGovernorate = gov.isEmpty ? null : gov;
      _selectedLat = lat;
      _selectedLng = lng;
      _locationIsApproximate = approx;
      _maybeSuggestSmartTitle();
    });
    unawaited(_refreshDistricts());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          _isAr
              ? 'تم اختيار: ${hit.cityAr}${approx ? ' (موقع تقريبي)' : ''}'
              : 'Selected: ${hit.cityEn}${approx ? ' (approximate)' : ''}',
        ),
      ),
    );
  }

  void _maybeSuggestSmartTitle({bool force = false}) {
    if (!force && _titleCtrl.text.trim().isNotEmpty) return;
    final typeLabel = PropertyTypeCatalog.label(_typeKey, _isAr);
    final purposeBit =
        _purchase ? (_isAr ? 'للشراء' : 'to buy') : (_isAr ? 'للإيجار' : 'to rent');
    final city = _cityForSubmit().trim();
    final districts = _districtsCtrl.text.trim();
    final suggested = PropertyListingDisplay.composeListingHeadline(
      typeLabel: typeLabel,
      purposeBit: purposeBit,
      city: city,
      district: districts.isNotEmpty ? districts : null,
      isAr: _isAr,
      asRequest: true,
    );
    if (suggested.trim().isEmpty) return;
    _titleCtrl.text = suggested.trim();
  }

  double? _parseMoney(String s) {
    final t = input_norm
        .normalizeAsciiDigits(AppMoney.stripSarMarks(s.trim()))
        .replaceAll(',', '')
        .replaceAll('٬', '')
        .replaceAll('٫', '.')
        .replaceAll(RegExp(r'[^0-9.]'), '');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  String? _requestBudgetLabel() {
    final min = _parseMoney(_budgetMinCtrl.text);
    final max = _parseMoney(_budgetMaxCtrl.text);
    if (min == null && max == null) return null;
    if (min != null && max != null) {
      return AppMoney.sarPhrase(
        '${min.toStringAsFixed(0)} - ${max.toStringAsFixed(0)}',
        isAr: _isAr,
      );
    }
    if (max != null) {
      return AppMoney.sarPhrase(max.toStringAsFixed(0), isAr: _isAr);
    }
    return AppMoney.sarPhrase('${min!.toStringAsFixed(0)}+', isAr: _isAr);
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
        if (!_purchase && _rentTerm.isEmpty) {
          _showSnack(_isAr ? 'حدّد مدة الإيجار' : 'Choose a rent period');
          return false;
        }
        if (!_purchase && _rentTerm == 'daily' && _rentStart == null) {
          _showSnack(_isAr ? 'حدّد التاريخ' : 'Choose a date');
          return false;
        }
        if (!_purchase &&
            _rentTerm.isNotEmpty &&
            _rentTerm != 'daily' &&
            _rentStart == null) {
          _showSnack(_isAr ? 'حدّد تاريخ البداية' : 'Choose a start date');
          return false;
        }
        return true;
      case 1:
        return true;
      case 2:
        if (_manualLocation || (_locations.isEmpty && !_locationsLoading)) {
          _applyManualLocationFields();
          if ((_selectedRegion ?? '').trim().isEmpty ||
              (_selectedGovernorate ?? '').trim().isEmpty ||
              _cityKey.trim().isEmpty) {
            _showSnack(
              _isAr
                  ? 'أدخل المنطقة والمحافظة والمدينة يدوياً أو حدّد على الخريطة'
                  : 'Enter region, governorate, and city manually or pick on the map',
            );
            return false;
          }
          return true;
        }
        if (_locations.isEmpty && !_locationsLoading) {
          _showSnack(
            _isAr
                ? 'تعذر تحميل بيانات المدن. استخدم الإدخال اليدوي.'
                : 'Could not load city data. Use manual entry.',
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
                ? 'المبلغ «من» يجب ألا يتجاوز «إلى»'
                : 'Min amount must not exceed max',
          );
          return false;
        }
        if (_publicNameCtrl.text.trim().isEmpty && _showRequesterNameOnCards) {
          _showSnack(
            _isAr
                ? 'أدخل الاسم الرباعي / المعروض للمهتمين أو أوقف إظهار الاسم'
                : 'Enter a display name or turn off showing your name',
          );
          _publicNameFocus.requestFocus();
          return false;
        }
        return true;
      default:
        return true;
    }
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
    await showAppModalBottomSheet<void>(
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
          _usedDefaultCover = false;
        });
      }
    } finally {
      suspendAutoLock.value = false;
      if (mounted) setState(() => _pickingCover = false);
    }
  }

  /// عند عدم اختيار صورة، نُعلّم الغلاف الذكي في قاعدة البيانات
  /// ([default_cover_used]) — يُعرض محلياً في كل بطاقات الطلب.
  void _markSmartDefaultCoverIfMissing() {
    if (_coverBytes != null && _coverBytes!.isNotEmpty) {
      _usedDefaultCover = false;
      return;
    }
    _usedDefaultCover = true;
  }

  Future<void> _submit() async {
    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(_isAr
              ? 'يجب الموافقة على الشروط والأحكام قبل النشر.'
              : 'You must accept the terms before publishing.'),
        ),
      );
      return;
    }
    _syncComposedTitle();
    for (var s = 0; s < _stepCount; s++) {
      if (!_validateStepBeforeLeave(s)) {
        setState(() => _step = s);
        _scrollStepToTop();
        return;
      }
    }
    if (_requestPriority == MarketPropertyRequestPriority.immediate &&
        (_instantCreditId ?? '').trim().isEmpty) {
      await _payForInstantPriority();
      if ((_instantCreditId ?? '').trim().isEmpty) return;
    }
    // — حماية من النشر المزدوج: تجاهل الضغط المتكرر بعد بدء النشر.
    if (_publishLock) return;
    final title = _titleCtrl.text.trim();
    final pub = _publicNameCtrl.text.trim();
    final city = (_selectedCityLabelInList ?? _cityKey).trim();
    final purposeWire = _purchase ? 'purchase' : 'rent';
    final fp = PublishContentFingerprintStore.build(
      title: title,
      city: city,
      price: num.tryParse(_budgetMaxCtrl.text.trim().replaceAll(',', '')) ??
          num.tryParse(_budgetMinCtrl.text.trim().replaceAll(',', '')),
      area: num.tryParse(_areaMinCtrl.text.trim().replaceAll(',', '')),
      deed: '',
      purpose: purposeWire,
    );
    final storedFp = await PublishContentFingerprintStore.readIfFresh();
    if (storedFp == fp) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'طلب مطابق نُشر للتو. راجع الرئيسية أو غيّر البيانات قبل إعادة النشر.'
                : 'An identical request was just published. Check Home or change data before republishing.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _publishLock = true;
    });
    setState(() => _markSmartDefaultCoverIfMissing());
    try {
      String? coverPath;
      final bytes = _coverBytes;
      if (!_usedDefaultCover && bytes != null && bytes.isNotEmpty) {
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

      Future<Map<String, dynamic>> doInsert(Map<String, dynamic> payload) async {
        try {
          final ins = await _sb
              .from('market_property_requests')
              .insert(payload)
              .select('id,request_public_code')
              .single();
          return Map<String, dynamic>.from(ins as Map);
        } on PostgrestException catch (e) {
          final detail = '${e.message} ${e.details ?? ''}'.toLowerCase();
          if (detail.contains('request_priority')) {
            if (_requestPriority == MarketPropertyRequestPriority.immediate) {
              rethrow;
            }
            payload.remove('request_priority');
            return doInsert(payload);
          }
          if (detail.contains('request_public_code') &&
              (detail.contains('column') ||
                  detail.contains('schema') ||
                  detail.contains('could not find'))) {
            final ins = await _sb
                .from('market_property_requests')
                .insert(payload)
                .select('id')
                .single();
            return Map<String, dynamic>.from(ins as Map);
          }
          rethrow;
        }
      }

      final isInstantNew = !_isEditing &&
          _requestPriority == MarketPropertyRequestPriority.immediate;

      var row = <String, dynamic>{
        'requester_id': (_sb.auth.currentUser?.id ?? widget.userId).trim(),
        if (!_isEditing)
          'status': isInstantNew ? 'draft' : 'published',
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
        if (_preferNew != null) 'prefer_new': _preferNew,
        'show_requester_name': _showRequesterNameOnCards,
        'requester_public_name':
            _showRequesterNameOnCards && pub.isNotEmpty ? pub : null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      // هوية الناشر داخل details لتجنّب أعمدة غير موجودة على السيرفر القديم.
      final identityMeta = <String, dynamic>{
        'publisher_public_name_source': _pubNameSource.name,
        'publisher_public_phone_source': PublicPhoneSource.hidden.name,
        'publisher_publish_presence': _publishPresenceOnCards,
      };
      if (coverPath != null) {
        row['cover_image_storage_path'] = coverPath;
      } else if (_usedDefaultCover) {
        row['cover_image_storage_path'] =
            AppBranding.smartDefaultCoverStorageSentinel;
      }
      if (_usedDefaultCover) {
        row['default_cover_used'] = true;
      }
      final details = _detailsPayloadForInsert();
      details.addAll(identityMeta);
      if (details.isNotEmpty) {
        row['details_json'] = details;
      } else if (_isEditing) {
        row['details_json'] = <String, dynamic>{};
      }
      Map<String, dynamic>? insertedMarket;
      try {
        if (_isEditing) {
          await _updateExistingRequest(Map<String, dynamic>.from(row));
        } else {
          insertedMarket = await doInsert(Map<String, dynamic>.from(row));
        }
      } on PostgrestException catch (e) {
        final detail = '${e.message} ${e.details ?? ''}'.toLowerCase();
        if (detail.contains('details_json')) {
          row.remove('details_json');
          if (_isEditing) {
            await _updateExistingRequest(Map<String, dynamic>.from(row));
          } else {
            insertedMarket = await doInsert(Map<String, dynamic>.from(row));
          }
        } else if (detail.contains('default_cover_used') &&
            detail.contains('does not exist')) {
          // — البيئة لم تطبّق ترحيل v9 بعد؛ نتابع بدون العلامة.
          row.remove('default_cover_used');
          if (_isEditing) {
            await _updateExistingRequest(Map<String, dynamic>.from(row));
          } else {
            insertedMarket = await doInsert(Map<String, dynamic>.from(row));
          }
        } else {
          rethrow;
        }
      }
      if (!mounted) return;
      AppHaptics.medium();
      if (!_isEditing &&
          _requestPriority == MarketPropertyRequestPriority.immediate) {
        final reqId = '${insertedMarket?['id'] ?? ''}'.trim();
        final cid = _instantCreditId?.trim() ?? '';
        if (reqId.isNotEmpty && cid.isEmpty) {
          try {
            await _sb
                .from('market_property_requests')
                .delete()
                .eq('id', reqId)
                .eq('requester_id', widget.userId);
          } catch (_) {}
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _isAr
                      ? PlatformFeeCatalog.of(context).instantRequiresPay(isAr: true)
                      : PlatformFeeCatalog.of(context).instantRequiresPay(isAr: false),
                ),
              ),
            );
          }
          setState(() {
            _saving = false;
            _publishLock = false;
          });
          return;
        }
        if (reqId.isNotEmpty && cid.isNotEmpty) {
          final consumed = await InstantMarketRequestPaymentService(_sb)
              .consumeCredit(creditId: cid, marketRequestId: reqId);
          if (consumed['ok'] != true && mounted) {
            try {
              await _sb
                  .from('market_property_requests')
                  .delete()
                  .eq('id', reqId)
                  .eq('requester_id', widget.userId);
            } catch (_) {}
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _isAr
                      ? 'تعذّر ربط دفع «فوري» — لم يُنشر الطلب. يمكنك استخدام الرصيد لاحقاً أو استرداده.'
                      : 'Instant payment link failed — request was not published. Credit remains for reuse or refund.',
                ),
              ),
            );
            setState(() {
              _saving = false;
              _publishLock = false;
            });
            return;
          } else {
            try {
              await _sb
                  .from('market_property_requests')
                  .update({
                    'status': 'published',
                    'updated_at': DateTime.now().toUtc().toIso8601String(),
                  })
                  .eq('id', reqId)
                  .eq('requester_id', widget.userId);
            } catch (_) {}
            setState(() {
              _instantCreditId = null;
              _instantBillingId = null;
            });
          }
        }
      }
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
      final codeRaw =
          (insertedMarket?['request_public_code'] ?? '').toString().trim();
      final codeLine = codeRaw.isNotEmpty
          ? (_isAr
              ? 'رقم الطلب العقاري: ${DisplayIds.tenDigit(codeRaw)}'
              : 'Request no.: ${DisplayIds.tenDigit(codeRaw)}')
          : null;
      final next = await showAdaptivePostPublishDialog(
        context: context,
        isAr: _isAr,
        leadingIcon: Icons.home_rounded,
        accentColor: const Color(0xFF0F766E),
        title: t?.marketPropertySubmitSuccessTitle ??
            (_isAr ? 'تم إرسال الطلب إلى الرئيسية' : 'Sent to Home'),
        body: t?.marketPropertySubmitSuccessBody ??
            (_isAr
                ? 'طلبك ظاهر للمهتمين في السوق العقاري. الرئيسية تُحدَّث فوراً وتفتح على طلبك.'
                : 'Your request is visible to interested marketers. Home refreshes instantly to your new request.'),
        statusChip: t?.listingPublishLiveStatusChip ??
            (_isAr ? 'منشور في الرئيسية' : 'Live on Home'),
        codeLine: codeLine,
        actions: [
          AdaptivePostPublishAction(
            id: 'another',
            label: t?.marketPropertySubmitAnother ??
                (_isAr ? 'طلب عقاري آخر' : 'Another request'),
            outlined: true,
          ),
          AdaptivePostPublishAction(
            id: 'home',
            label: t?.marketPropertySubmitGoHome ??
                (_isAr ? 'الرئيسية' : 'Home'),
            icon: Icons.home_outlined,
            filled: true,
          ),
        ],
      );
      if (!mounted) return;
      unawaited(PublishContentFingerprintStore.save(fp));
      setState(() => _publishLock = false);
      if (next == 'another') {
        // صفّر الحقول فوراً ثم امسح المسودة في الخلفية.
        unawaited(_clearDraftAndForm());
        return;
      }
      if (!_isEditing) {
        await WizardFormDraft.clear(
          namespace: _draftNamespace,
          userId: widget.userId,
        );
      }
      if (!mounted) return;
      // أغلِق النموذج داخل جسم اللوحة → الرئيسية (لا تُعد بناء ويب).
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop(
          PostPublishNavResult.liveHome(
            marketRequestId:
                '${insertedMarket?['id'] ?? ''}'.trim().isEmpty
                    ? null
                    : '${insertedMarket?['id'] ?? ''}'.trim(),
          ),
        );
      } else {
        await PostAuthNavigation.openDashboard(context);
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _publishLock = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _publishLock = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      // — `_publishLock` يبقى مرفوعاً حتى إغلاق حوار النجاح ورؤية رقم الطلب.
      //   عند النجاح يُحرّر داخل الحوار قبل النافيجيشن (في الكود أعلاه).
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
        return _isAr ? 'المبلغ المحدد والمراجعة' : 'Amount & review';
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
    final busy = _saving || _publishLock || _pickingCover;

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        );

    final stepBody = <Widget>[
      if (_step == 0) ...[
        Text(
          _isAr
              ? 'يظهر طلبك لجميع الشركاء المهتمين. أكمل الخطوات بالترتيب.'
              : 'Your request is shown to all interested partners. Complete the steps in order.',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            fontFamily: 'Cairo',
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<MarketPropertyRequestPriority>(
          value: _priorityChoices.contains(_requestPriority)
              ? _requestPriority
              : MarketPropertyRequestPriority.standard,
          decoration: InputDecoration(
            labelText: t?.marketRequestUrgencyTitle ??
                (_isAr ? 'درجة الإلحاح' : 'Request urgency'),
            border: const OutlineInputBorder(),
          ),
          items: _priorityChoices
              .map(
                (p) => DropdownMenuItem(
                  value: p,
                  child: Row(
                    children: [
                      Expanded(child: Text(_priorityMenuLabel(t, p))),
                      if (p == MarketPropertyRequestPriority.immediate)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 6),
                          child: _instantFeeChip(cs),
                        ),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: busy
              ? null
              : (v) {
                  if (v == null) return;
                  unawaited(_onPriorityChanged(v));
                },
        ),
        if ((_instantCreditId ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Material(
            color: cs.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isAr
                        ? 'رصيد فوري جاهز — يُخصم لهذا الطلب عند النشر.'
                        : 'Instant credit ready — applied when you publish.',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => unawaited(_cancelUnusedInstantCredit()),
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(
                      PlatformFeeCatalog.of(context).cancelInstantRefund(isAr: _isAr),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else if (_loadingInstantCredit)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        const SizedBox(height: 14),
        Text(
          _isAr ? 'الغرض' : 'Purpose',
          style: const TextStyle(fontWeight: FontWeight.w900, fontFamily: 'Cairo'),
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
                if (_purchase) _rentTerm = '';
                _syncComposedTitle();
              });
            },
          ),
        ),
        if (!_purchase) RentTermScheduleFields(
          isAr: _isAr,
          busy: busy,
          rentTerm: _rentTerm,
          rentDays: _rentDays,
          rentWeeks: _rentWeeks,
          rentMonths: _rentMonths,
          rentYears: _rentYears,
          rentStart: _rentStart,
          rentEnd: _rentEndComputed,
          onTerm: _applyRentTerm,
          onDays: (n) => setState(() => _rentDays = n),
          onWeeks: (n) => setState(() => _rentWeeks = n),
          onMonths: _setRentMonths,
          onYears: (n) => setState(() => _rentYears = n),
          onPickStart: () => unawaited(_pickRentStart()),
        ),
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
                  setState(() {
                    _typeKey = v;
                    for (final k in _requestAmenityToggles.keys) {
                      _requestAmenityToggles[k] = false;
                    }
                    _syncComposedTitle();
                  });
                },
        ),
        if (_wantsResidentialDetailFields()) ...[
          const SizedBox(height: 16),
          Text(
            _isAr ? 'تفاصيل سكنية' : 'Residential details',
            style: const TextStyle(fontWeight: FontWeight.w900, fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SmartCountField(
                  label: _isAr ? 'غرف نوم' : 'Bedrooms',
                  value: _bedrooms,
                  onChanged: (v) => setState(() => _bedrooms = v),
                  isAr: _isAr,
                  enabled: !busy,
                  min: 0,
                  maxPreset: 12,
                  allowClear: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SmartCountField(
                  label: _isAr ? 'دورات مياه' : 'Bathrooms',
                  value: _bathrooms,
                  onChanged: (v) => setState(() => _bathrooms = v),
                  isAr: _isAr,
                  enabled: !busy,
                  min: 0,
                  maxPreset: 10,
                  allowClear: true,
                ),
              ),
            ],
          ),
        ],
        if (_wantsAmenityFields()) ...[
          const SizedBox(height: 14),
          Text(
            _isAr ? 'الخدمات المطلوبة' : 'Amenities',
            style: const TextStyle(fontWeight: FontWeight.w900, fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 8),
          AmenityEqualSelectGrid(
            typeCode: _typeKey,
            values: _requestAmenityToggles,
            isAr: _isAr,
            enabled: !busy,
            onToggle: (k, v) => setState(() => _requestAmenityToggles[k] = v),
          ),
        ],
        const SizedBox(height: 14),
        EqualOptionTileGrid(
          children: [
            EqualSelectTile(
              label: _isAr ? 'مفروش' : 'Furnished',
              selected: _furnishedWanted == true,
              enabled: !busy,
              onTap: () => setState(() => _furnishedWanted =
                  _furnishedWanted == true ? null : true),
            ),
            EqualSelectTile(
              label: _isAr ? 'غير مفروش' : 'Unfurnished',
              selected: _furnishedWanted == false,
              enabled: !busy,
              onTap: () => setState(() => _furnishedWanted =
                  _furnishedWanted == false ? null : false),
            ),
            EqualSelectTile(
              label: _isAr ? 'جديدة' : 'New',
              selected: _preferNew == true,
              enabled: !busy,
              onTap: () => setState(
                  () => _preferNew = _preferNew == true ? null : true),
            ),
            EqualSelectTile(
              label: _isAr ? 'ليست جديدة' : 'Not new',
              selected: _preferNew == false,
              enabled: !busy,
              onTap: () => setState(
                  () => _preferNew = _preferNew == false ? null : false),
            ),
          ],
        ),
      ],
      if (_step == 2) ...[
        if (_locationsLoading) ...[
          const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 10),
        ],
        Text(
          _isAr
              ? 'المنطقة ثم المحافظة ثم المدينة ثم الحي.'
              : 'Region, then governorate, then city, then district.',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        if (_locations.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: busy
                  ? null
                  : () => setState(() => _manualLocation = !_manualLocation),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(
                _manualLocation
                    ? (_isAr ? 'العودة للقوائم الرسمية' : 'Back to official lists')
                    : (_isAr ? 'إدخال يدوي للموقع' : 'Enter location manually'),
              ),
            ),
          ),
        if (_manualLocation || (!_locationsLoading && _locations.isEmpty)) ...[
          if (!_locationsLoading && _locations.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _isAr
                    ? 'تعذر جلب بيانات الهيئة. أكمل الموقع يدوياً أو من الخريطة.'
                    : 'Authority city data is unavailable. Complete location manually or from the map.',
                style: TextStyle(color: cs.error, fontWeight: FontWeight.w700),
              ),
            ),
          AqarTextField(
            controller: _manualRegionCtrl,
            enabled: !busy,
            decoration: deco(_isAr ? 'المنطقة *' : 'Region *'),
            onChanged: (v) => _selectedRegion = v.trim(),
          ),
          const SizedBox(height: 10),
          AqarTextField(
            controller: _manualGovCtrl,
            enabled: !busy,
            decoration: deco(_isAr ? 'المحافظة *' : 'Governorate *'),
            onChanged: (v) => _selectedGovernorate = v.trim(),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AqarTextField(
                  controller: _manualCityCtrl,
                  enabled: !busy,
                  decoration: deco(_isAr ? 'المدينة *' : 'City *'),
                  onChanged: (v) => _cityKey = v.trim(),
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
          const SizedBox(height: 10),
          AqarTextField(
            controller: _districtsCtrl,
            enabled: !busy,
            decoration: deco(_isAr ? 'الحي' : 'District'),
          ),
          if (_selectedLat != null && _selectedLng != null) ...[
            const SizedBox(height: 10),
            AqarTextField(
              controller: TextEditingController(
                text: _selectedLat!.toStringAsFixed(6),
              ),
              readOnly: true,
              decoration: deco(_isAr ? 'خط العرض' : 'Latitude'),
            ),
            const SizedBox(height: 8),
            AqarTextField(
              controller: TextEditingController(
                text: _selectedLng!.toStringAsFixed(6),
              ),
              readOnly: true,
              decoration: deco(_isAr ? 'خط الطول' : 'Longitude'),
            ),
          ],
        ] else if (!_locationsLoading && _locations.isNotEmpty) ...[
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
            AqarTextField(
              controller: TextEditingController(
                text: _selectedLat!.toStringAsFixed(6),
              ),
              readOnly: true,
              decoration: deco(_isAr ? 'خط العرض' : 'Latitude'),
            ),
            const SizedBox(height: 8),
            AqarTextField(
              controller: TextEditingController(
                text: _selectedLng!.toStringAsFixed(6),
              ),
              readOnly: true,
              decoration: deco(_isAr ? 'خط الطول' : 'Longitude'),
            ),
            const SizedBox(height: 8),
            AqarTextField(
              controller: TextEditingController(text: _coordsCombined),
              readOnly: true,
              decoration: InputDecoration(
                labelText: _isAr ? 'الإحداثي' : 'Coordinates',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _isAr ? 'نسخ' : 'Copy',
                  onPressed: _copyCoords,
                  icon: const Icon(Icons.copy_outlined),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (_districtOptions.isNotEmpty)
            DropdownButtonFormField<String>(
              value: _districtsCtrl.text.trim().isNotEmpty &&
                      _districtOptions.contains(_districtsCtrl.text.trim())
                  ? _districtsCtrl.text.trim()
                  : null,
              decoration: deco(_isAr ? 'الحي' : 'District'),
              isExpanded: true,
              items: _districtOptions
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() {
                        _districtsCtrl.text = v;
                        _syncComposedTitle();
                      });
                    },
            )
          else
            AqarTextField(
              controller: _districtsCtrl,
              enabled: !busy,
              decoration: deco(_isAr ? 'الحي' : 'District'),
            ),
        ],
      ],
      if (_step == 3) ...[
        Text(
          _isAr ? 'المبلغ والمساحة ثم مراجعة الطلب.' : 'Amount, area, then review.',
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
                        label: _isAr ? 'المبلغ من' : 'Amount min',
                        enabled: !busy,
                        isAr: _isAr,
                        alignOpposite: true,
                        inputFormatters: _moneyInputFormatters,
                      ),
                      const SizedBox(height: 10),
                      BudgetTextField(
                        controller: _budgetMaxCtrl,
                        label: _isAr ? 'المبلغ إلى' : 'Amount max',
                        enabled: !busy,
                        textInputAction: TextInputAction.next,
                        isAr: _isAr,
                        alignOpposite: true,
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
                          label: _isAr ? 'المبلغ من' : 'Amount min',
                          enabled: !busy,
                          isAr: _isAr,
                          alignOpposite: true,
                          inputFormatters: _moneyInputFormatters,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: BudgetTextField(
                          controller: _budgetMaxCtrl,
                          label: _isAr ? 'المبلغ إلى' : 'Amount max',
                          enabled: !busy,
                          textInputAction: TextInputAction.next,
                          isAr: _isAr,
                          alignOpposite: true,
                          inputFormatters: _moneyInputFormatters,
                        ),
                      ),
                    ],
                  );
            return budgetRow;
          },
        ),
        const SizedBox(height: 12),
        AqarTextField(
          controller: _areaMinCtrl,
          enabled: !busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _moneyInputFormatters,
          decoration: InputDecoration(
            labelText: _isAr ? 'مساحة لا تقل عن (م²)' : 'Min area (m²)',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        AqarTextField(
          controller: _titleCtrl,
          readOnly: true,
          decoration: InputDecoration(
            labelText: _isAr ? 'عنوان الطلب' : 'Request title',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        AqarTextField(
          controller: _descCtrl,
          enabled: !busy,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: _isAr ? 'تفاصيل العقار' : 'Property details',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: _isAr ? 'تفاصيل مناسبة' : 'Suggest details',
              onPressed: busy ? null : _fillSmartDetails,
              icon: const Icon(Icons.auto_awesome_outlined),
            ),
          ),
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
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(
            _isAr
                ? 'إظهار اسمي في السوق العقاري'
                : 'Show my name on the market',
            style: const TextStyle(fontWeight: FontWeight.w800, height: 1.25),
          ),
          subtitle: Text(
            _isAr
                ? 'اختياري: الاسم الرباعي أو اسم المكتب/المؤسسة/الشركة أو المستعار. الجوال لا يظهر.'
                : 'Optional official or alias name. Phone stays hidden.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          value: _showRequesterNameOnCards,
          onChanged: busy
              ? null
              : (v) => setState(() => _showRequesterNameOnCards = v),
        ),
        if (_showRequesterNameOnCards) ...[
          const SizedBox(height: 8),
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
                child: AqarTextField(
                  controller: _publicNameCtrl,
                  focusNode: _publicNameFocus,
                  enabled: !busy,
                  decoration: InputDecoration(
                    labelText: _isAr
                        ? 'الاسم الظاهر للمهتمين'
                        : 'Name shown to responders',
                    hintText: _isAr
                        ? 'يُقترح من هويتك (معتمد أو مستعار)'
                        : 'Suggested from your identity prefs',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        PublisherIdentityOptionsCard(
          isAr: _isAr,
          compact: true,
          enabled: !busy,
          hidePhoneOptions: true,
          marketContactLocked: true,
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
            setState(() {
              _pubNameSource = v;
              final n = PublisherIdentityPrefs.instance
                  .resolvedPublicName(isAr: _isAr);
              if (n.isNotEmpty) _publicNameCtrl.text = n;
            });
          },
          onPublishPresenceChanged: (v) async {
            await PublisherIdentityPrefs.instance.setPublishPresenceOnCards(v);
            if (!mounted) return;
            setState(() => _publishPresenceOnCards = v);
          },
        ),
        const SizedBox(height: 14),
        TermsAcceptanceCheckbox(
          isAr: _isAr,
          value: _termsAccepted,
          onChanged: busy
              ? null
              : (v) => setState(() => _termsAccepted = v == true),
          onOpenTerms: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => PlatformPoliciesScreen(isAr: _isAr),
              ),
            );
          },
        ),
      ],
    ];

    final confirmPop =
        !_isEditing && _hasUnsavedWizardInput();
    // — أثناء النشر يُمنع الرجوع كلياً حتى لا يُنشر الطلب مرتين.
    final isPublishing = _saving || _publishLock;
    return PopScope(
      canPop: !confirmPop && !isPublishing,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (isPublishing) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(_isAr
                    ? 'جاري نشر الطلب… يرجى الانتظار حتى ظهور رقم الطلب.'
                    : 'Publishing request… please wait for the confirmation.'),
              ),
            );
          }
          return;
        }
        await _handleFormExitFromPop(result);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: AppPageCloseButton(
                isArabic: _isAr,
                onPressed: () => unawaited(_onComposerClosePressed()),
              ),
        title: Text(
          _isEditing
              ? (_isAr ? 'تعديل الطلب العقاري' : 'Edit property request')
              : (_isAr ? 'طلب عقاري' : 'Property request'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (!_isEditing)
            IconButton(
              tooltip: _isAr ? 'حفظ المسودة' : 'Save draft',
              onPressed: _saving
                  ? null
                  : () => unawaited(_persistDraft()),
              icon: const Icon(Icons.save_outlined),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: ComposerStepConstellation(
              step: _step + 1,
              total: _stepCount,
              accent: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        ),
        body: AppKeyboardPad(
          extra: 8,
          child: _saving
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogoLoading(),
                  const SizedBox(height: 16),
                  Text(
                    _isAr
                        ? 'جاري مراجعة التفاصيل والنشر'
                        : 'Reviewing details & publishing',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final padH = min(32.0, max(12.0, constraints.maxWidth * 0.04));
                final maxBody = min(constraints.maxWidth, 980.0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListView(
                        controller: _stepScrollCtrl,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
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
                                  child: (_saving || _publishLock)
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: AppLogoLoading(
                                                compact: true,
                                                size: 16,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _isAr
                                                  ? 'جاري مراجعة التفاصيل والنشر…'
                                                  : 'Reviewing details & publishing…',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ],
                                        )
                                      : Text(
                                          _isAr
                                              ? 'نشر الطلب'
                                              : 'Publish request',
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
        ),
      ),
    );
  }
}
