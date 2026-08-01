// lib/screens/settings_page.dart
import 'dart:async' show unawaited;
import 'dart:convert' show jsonDecode;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/utils/search_normalize.dart';
import '../core/utils/compound_display_name.dart';
import '../core/config/app_config.dart';
import '../core/input/saudi_input_formatters.dart';
import '../core/gestures/app_gesture_preferences.dart';
import '../core/motion/app_motion_policy.dart';
import '../core/motion/app_motion_prefs.dart';
import '../core/utils/listing_date_display.dart';
import '../core/utils/profile_greeting_from_row.dart';
import '../core/presence/presence_display_prefs.dart';
import '../core/permissions/runtime_permission_helper.dart';
import '../l10n/app_localizations.dart';
import '../main.dart'
    show
        langNotifier,
        setAppLang,
        setAppTheme,
        setAppHapticsEnabled,
        suspendAutoLock,
        themeModeNotifier,
        kPrefBgLockGraceMinutes,
        kAppBackgroundLockGraceMinutesDefault,
        setAppBackgroundLockGraceMinutes,
        textScaleNotifier,
        setAppTextScaleFactor;
import '../core/haptics/app_haptics.dart';
import '../core/notifications/in_app_notification_sound.dart';
import '../core/notifications/chat_message_sound.dart';
import '../core/theme/app_accent.dart';
import '../core/session/user_appearance_session.dart';
import '../core/theme/app_appearance_bridge.dart';
import '../core/compliance/platform_compliance_config.dart';
import '../routes.dart';
import '../core/onboarding/device_first_run_prefs.dart';
import 'session_history_screen.dart';
import 'switch_account_screen.dart';
import 'browse_organizations_screen.dart';
import '../services/fast_login_service.dart';
import '../services/org_team_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_confirm_dialog.dart';
import '../models/saudi_location.dart';
import '../services/saudi_locations_service.dart';
import 'map_picker_page.dart';
import '../widgets/field_group_frame.dart';
import '../core/input/input_normalizers.dart';
import '../services/account_completion_service.dart';
import '../services/chat_notification_prefs.dart';
import '../core/profile/publisher_identity_prefs.dart';
import '../widgets/publisher_identity_options_card.dart';
import '../services/user_listing_preferences_service.dart';
import '../services/user_install_session_service.dart';
import '../core/security/device_display_labels.dart';
import '../screens/device_management_page.dart';

import 'consent_preferences_screen.dart';
import 'platform_policies_screen.dart';
import 'profile_enrollment_gate_screen.dart';
import 'regulatory_operator_checklist_screen.dart';
import 'support_page.dart';

/// أقسام الإعدادات — ويب: تبويب لكل قسم، جوال: صف يفتح الشاشة الفرعية.
enum _SettingsSection {
  profile,
  accountHub,
  security,
  organization,
  devices,
  sessions,
  discovery,
  appDevice,
  permissions,
  notificationsPreferences,
  platformCompliance,
  gestures,
  danger,
}

class SettingsPage extends StatefulWidget {
  /// عند `true`: بدون [AppBar] (يُستخدم داخل لوحة التحكم الخارجية لتفادي سهمي رجوع).
  const SettingsPage({
    super.key,
    this.embedAppBar = false,
    this.focusPresenceDisplay = false,
    this.focusProfileCompletion = false,
  });

  final bool embedAppBar;

  /// يمرّر إلى قسم الملف ويركّز على إعدادات عرض الظهور.
  final bool focusPresenceDisplay;

  /// يفتح قسم الملف ويركّز على استكمال البيانات الناقصة.
  final bool focusProfileCompletion;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// نفس مساحة التخزين المستخدمة للعقارات؛ مجلد منفصل للصور الشخصية.
  static const String _avatarStorageBucket = 'property-images';
  static const String _avatarFolder = 'user-avatars';
  static const int _avatarMaxSide = 1024;
  static const int _avatarJpegQuality = 82;
  static const int _avatarMaxInputBytes = 12 * 1024 * 1024; // 12 MB قبل الضغط

  bool _pinEnabled = false;
  bool _canBio = false;
  bool _faceOn = false;
  bool _fpOn = false;
  bool _faceHw = false;
  bool _fpHw = false;

  int _graceMinutes = kAppBackgroundLockGraceMinutesDefault;
  String _appVersion = '';
  List<String> _deviceLines = [];
  List<String> _permissionLines = [];

  bool _uploadingPhoto = false;

  // ===== User/profile =====
  String _fullDisplayName = '';
  String _email = '';
  String _phone = '';
  String _avatarUrl = '';

  /// نوع الحساب (فرد / مسوّق / مكتب …) من العمود account_type إن وُجد
  String _accountCategory = '';

  /// دور/صلاحية من العمود role إن وُجد
  String _roleKey = 'user';

  String _accountStatus = 'active';
  String _createdAt = '';

  /// الرقم الوطني الموحّد (700…) إن وُجد في الملف
  String _unifiedNationalDisplay = '';

  /// الرقم العمومي 10 أرقام (public_member_id) — فرق/مكاتب
  String _publicMemberId = '';
  String _accountTypeRaw = '';

  /// حفظ لغة الواجهة مع حساب المستخدم (وليس الجهاز فقط).
  bool _syncLangWithAccount = true;

  /// حفظ وضع الفاتح/الداكن مع حساب المستخدم.
  bool _syncThemeWithAccount = true;

  bool _unifiedNationalObscured = true;
  bool _chatLastSeenHidden = false;

  final GlobalKey _presenceDisplayKey = GlobalKey();
  final GlobalKey _profileCompletionKey = GlobalKey();
  List<String> _missingProfileFields = const [];
  bool _presencePrefsLoaded = false;
  bool _presenceShowListing = true;
  bool _presenceShowRequest = true;
  bool _presenceShowChat = true;
  DateTime? _presenceHideUntil;

  String _officialName = '';
  String _displayAlias = '';
  String _secondaryPhone = '';
  PublicNameSource _publicNameSource = PublicNameSource.official;
  PublicPhoneSource _publicPhoneSource = PublicPhoneSource.primary;
  bool _publishPresenceOnCards = true;

  // ===== Devices / Sessions =====
  List<Map<String, dynamic>> _devices = [];
  List<Map<String, dynamic>> _sessions = [];

  /// صاحب مؤسسة (مكتب/مؤسسة/شركة) — يظهر روابط إدارة الفريق والمراقبة.
  bool _orgOwner = false;

  bool _chatNotificationsEnabled = true;
  bool _chatMessageSoundEnabled = true;

  /// عرض مدينة الاستكشاف الافتراضية بلسان الواجهة (المفتاح في [SharedPreferences]).
  String _preferredExploreCityDisplay = '';
  bool _hapticsEnabled = true;
  bool _motionEnabled = true;
  bool _inAppSoundEnabled = true;
  bool _swipeBackEnabled = true;
  bool _edgeOnlySwipeBack = false;
  bool _keyboardBackEnabled = true;

  /// عرض تواريخ الإعلانات (يُحفظ في [SharedPreferences]).
  ListingDateDisplayZone _listingDateZone = ListingDateDisplay.zone;

  /// إحصاء بلاغات مُسجَّل محلياً (حدّ المعدّل والملخص في الملف الشخصي).
  int _reportCountProperties = 0;
  int _reportCountRequests = 0;
  int _reportCountLast30d = 0;

  bool get _isAr => langNotifier.value == 'ar';
  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// قائمة أقسام على الشاشات الضيقة (جوال أصلي أو ويب ضيق/تابلت).
  bool get _useCompactSettingsHub {
    if (_isMobile) return true;
    final w = MediaQuery.sizeOf(context).width;
    // ويب ويندوز العريض → تبويبات؛ جوال ويب / آيباد عمودي → قائمة أقسام.
    return w < 900;
  }

  final _sb = Supabase.instance.client;

  /// جوال: `null` = قائمة الأقسام، وإلا محتوى القسم المختار.
  _SettingsSection? _mobileDetail;

  /// يُزاد بعد كل تحميل/حفظ للملف حتى تُعاد بناء تبويبات الويب الكسولة.
  int _settingsContentEpoch = 0;

  void _bumpSettingsContent() {
    _settingsContentEpoch++;
  }

  @override
  void initState() {
    super.initState();

    _loadUser();
    _loadOrgOwnerFlag();
    _loadFastLogin();
    _loadDevices();
    _loadGraceMinutes();
    unawaited(_loadDeviceAndAppInfo());
    unawaited(_loadPermissionSummary());
    unawaited(_loadChatNotificationPref());
    unawaited(_loadChatMessageSoundPref());
    unawaited(_loadHapticsPref());
    unawaited(_loadMotionPref());
    unawaited(_loadInAppSoundPref());
    unawaited(_loadGesturePrefs());
    unawaited(_loadPreferredExploreCity());
    unawaited(_loadLocalReportStats());
    _listingDateZone = ListingDateDisplay.zone;
    unawaited(_loadSyncLangPref());
    unawaited(_loadSyncThemePref());
    unawaited(_loadPresenceDisplayPrefs());
    if (widget.focusPresenceDisplay || widget.focusProfileCompletion) {
      _mobileDetail = _SettingsSection.profile;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.focusPresenceDisplay) {
          _scrollToPresenceDisplay();
        } else if (widget.focusProfileCompletion) {
          _scrollToProfileCompletion();
        }
      });
    }
  }

  Future<void> _loadPresenceDisplayPrefs() async {
    final prefs = PresenceDisplayPrefs.instance;
    await prefs.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _presencePrefsLoaded = true;
      _presenceShowListing = prefs.showOnListingCards;
      _presenceShowRequest = prefs.showOnRequestCards;
      _presenceShowChat = prefs.showOnChat;
      _presenceHideUntil = prefs.hideUntil;
    });
    if (widget.focusPresenceDisplay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToPresenceDisplay();
      });
    }
  }

  void _scrollToPresenceDisplay() {
    final ctx = _presenceDisplayKey.currentContext;
    if (ctx == null) {
      // قد لا يكون القسم مبنياً بعد في التبويب الكسول — أعد المحاولة.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c2 = _presenceDisplayKey.currentContext;
        if (c2 == null) return;
        Scrollable.ensureVisible(
          c2,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: 0.12,
        );
      });
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.12,
    );
  }

  void _scrollToProfileCompletion() {
    final ctx = _profileCompletionKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  String _accountStatusLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'active':
      case 'enabled':
      case 'ok':
        return _isAr ? 'نشط' : 'Active';
      case 'pending':
      case 'pending_review':
        return _isAr ? 'قيد المراجعة' : 'Pending review';
      case 'suspended':
      case 'disabled':
      case 'banned':
        return _isAr ? 'موقوف' : 'Suspended';
      case 'incomplete':
        return _isAr ? 'غير مكتمل' : 'Incomplete';
      case 'rejected':
        return _isAr ? 'مرفوض' : 'Rejected';
      default:
        if (raw.trim().isEmpty) return _isAr ? 'نشط' : 'Active';
        return _isAr ? 'حالة غير معروفة' : 'Unknown status';
    }
  }

  Widget _profileFactRow({
    required String label,
    required String value,
    Widget? trailing,
    VoidCallback? onEdit,
    String? editLabel,
  }) {
    final cs = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 420;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value.isEmpty ? '—' : value,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          height: 1.25,
                        ),
                      ),
                      if (onEdit != null || trailing != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (trailing != null) trailing,
                            const Spacer(),
                            if (onEdit != null)
                              TextButton(
                                onPressed: onEdit,
                                child: Text(
                                  editLabel ?? (_isAr ? 'تعديل' : 'Edit'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 132,
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurfaceVariant,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          value.isEmpty ? '—' : value,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (trailing != null) trailing,
                      if (onEdit != null)
                        TextButton(
                          onPressed: onEdit,
                          child: Text(
                            editLabel ?? (_isAr ? 'تعديل' : 'Edit'),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: cs.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _keyboardAwareDialogBody(Widget child) {
    return Builder(
      builder: (ctx) {
        final inset = MediaQuery.viewInsetsOf(ctx).bottom;
        return AnimatedPadding(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: inset > 0 ? inset * 0.35 : 0),
          child: SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: child,
          ),
        );
      },
    );
  }

  void _showTempSnack(String message, {Duration? duration}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 3),
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Future<void> _showEditPhoneDialog() async {
    final primaryLocked = digitsOnly(normalizeAsciiDigits(_phone)).length >= 10;
    final c = TextEditingController(
      text: primaryLocked
          ? digitsOnly(normalizeAsciiDigits(_secondaryPhone))
          : digitsOnly(normalizeAsciiDigits(_phone)),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          primaryLocked
              ? (_isAr ? 'الجوال الإضافي' : 'Additional phone')
              : (_isAr ? 'إضافة رقم الجوال الأساسي' : 'Add primary phone'),
        ),
        content: _keyboardAwareDialogBody(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (primaryLocked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _isAr
                        ? 'الرقم الأساسي ($_phone) ثابت ولا يُعدّل. أضف جوالاً إضافياً صالحاً (05xxxxxxxx) للظهور أو للرسائل لاحقاً.'
                        : 'Primary ($_phone) is locked. Add a valid extra mobile (05xxxxxxxx) for public display or future SMS.',
                    style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35),
                  ),
                ),
              AqarTextField(
                controller: c,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹+]')),
                  LengthLimitingTextInputFormatter(16),
                ],
                decoration: InputDecoration(
                  hintText: '05xxxxxxxx',
                  helperText: _isAr
                      ? 'صيغة سعودية صحيحة — ستُربط لاحقاً بالرسائل النصية'
                      : 'Valid Saudi mobile — later linked to SMS',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'حفظ' : 'Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      c.dispose();
      return;
    }
    try {
      if (primaryLocked) {
        await PublisherIdentityPrefs.instance.saveSecondaryPhone(c.text);
      } else {
        await AccountCompletionService.savePhone(sb: _sb, phoneRaw: c.text);
      }
      if (!mounted) return;
      await _loadUser();
      _showTempSnack(
        primaryLocked
            ? (_isAr ? 'تم حفظ الجوال الإضافي' : 'Extra phone saved')
            : (_isAr ? 'تم حفظ الجوال الأساسي' : 'Primary phone saved'),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      _showTempSnack(
        msg.contains('primary_phone_locked')
            ? (_isAr
                ? 'الرقم الأساسي لا يُعدّل — استخدم الجوال الإضافي'
                : 'Primary phone is locked — use the extra phone')
            : (_isAr
                ? 'تعذر الحفظ — استخدم صيغة 05xxxxxxxx'
                : 'Could not save — use 05xxxxxxxx'),
      );
    } finally {
      c.dispose();
    }
  }

  Future<void> _showEditDisplayNameDialog() async {
    final c = TextEditingController(
      text: _displayAlias.isNotEmpty ? _displayAlias : _fullDisplayName,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isAr ? 'اسم الظهور المستعار' : 'Display alias'),
        content: _keyboardAwareDialogBody(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isAr
                    ? 'هذا الاسم المستعار للبطاقات والدردشة عند اختياره. الاسم/الصفة المعتمدة تبقى للمعاملات الرسمية.'
                    : 'Alias for cards/chat when selected. Official registered name stays for formal deals.',
                style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35),
              ),
              const SizedBox(height: 10),
              AqarTextField(
                controller: c,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: _isAr
                      ? 'مثال: اسم مختصر للظهور'
                      : 'e.g. short public alias',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'حفظ' : 'Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      c.dispose();
      return;
    }
    final normalized = CompoundDisplayName.normalize(c.text);
    try {
      await AccountCompletionService.saveDisplayName(
        sb: _sb,
        displayName: normalized,
        isAr: _isAr,
      );
      await PublisherIdentityPrefs.instance.saveDisplayAlias(normalized);
      if (!mounted) return;
      setState(() {
        _bumpSettingsContent();
        _displayAlias = normalized;
        _fullDisplayName = normalized.isEmpty ? _fullDisplayName : normalized;
      });
      try {
        final prefs = await SharedPreferences.getInstance();
        if (normalized.isNotEmpty) {
          await prefs.setString('rememberDisplayName', normalized);
        }
      } catch (_) {}
      await _loadUser();
      if (!mounted) return;
      _showTempSnack(_isAr ? 'تم حفظ اسم الظهور' : 'Display alias saved');
    } catch (_) {
      if (!mounted) return;
      _showTempSnack(_isAr ? 'تعذر حفظ الاسم' : 'Could not save name');
    } finally {
      c.dispose();
    }
  }

  Future<void> _pickPresenceHideUntil() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    final until = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    await PresenceDisplayPrefs.instance.setHideUntil(until);
    if (!mounted) return;
    setState(() => _presenceHideUntil = until);
  }

  Future<void> _loadGesturePrefs() async {
    final values = await Future.wait<bool>([
      AppGesturePreferences.swipeBackEnabled(),
      AppGesturePreferences.edgeOnlySwipeBack(),
      AppGesturePreferences.keyboardBackEnabled(),
    ]);
    if (!mounted) return;
    setState(() {
      _swipeBackEnabled = values[0];
      _edgeOnlySwipeBack = values[1];
      _keyboardBackEnabled = values[2];
    });
  }

  Future<void> _loadSyncLangPref() async {
    final v = await UserAppearanceSession.readSyncLangWithAccount();
    if (!mounted) return;
    setState(() => _syncLangWithAccount = v);
  }

  Future<void> _loadSyncThemePref() async {
    final v = await UserAppearanceSession.readSyncThemeWithAccount();
    if (!mounted) return;
    setState(() => _syncThemeWithAccount = v);
  }

  Future<void> _loadLocalReportStats() async {
    final s = await UserListingPreferencesService.reportStatsSummary();
    if (!mounted) return;
    setState(() {
      _reportCountProperties = s.propertyReports;
      _reportCountRequests = s.requestReports;
      _reportCountLast30d = s.last30d;
    });
  }

  Future<void> _pickListingDateZone() async {
    final picked = await showModalBottomSheet<ListingDateDisplayZone>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  _isAr
                      ? 'منطقة عرض التواريخ في البطاقات'
                      : 'Time zone for listing dates',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              ...ListingDateDisplayZone.values.map((z) {
                return ListTile(
                  leading: Icon(
                    z == _listingDateZone
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_off_rounded,
                    color: z == _listingDateZone
                        ? Theme.of(ctx).colorScheme.primary
                        : Theme.of(ctx).colorScheme.outline,
                  ),
                  title: Text(
                    _isAr
                        ? ListingDateDisplay.zoneLabelAr(z)
                        : ListingDateDisplay.zoneLabelEn(z),
                  ),
                  onTap: () => Navigator.pop(ctx, z),
                );
              }),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    await ListingDateDisplay.saveZone(picked);
    setState(() => _listingDateZone = picked);
  }

  Future<String> _resolveExploreCityLabel(String key) async {
    if (key.isEmpty || key == 'all') {
      return _isAr
          ? 'الكل — كما في فلتر الرئيسية'
          : 'All — same as home filter';
    }
    try {
      final all = await SaudiLocationsService.instance.loadAll();
      for (final L in all) {
        if (L.cityEn == key || L.cityAr == key) {
          return _isAr ? L.cityAr : L.cityEn;
        }
      }
    } catch (_) {}
    return key;
  }

  Future<void> _loadPreferredExploreCity() async {
    try {
      final p = await SharedPreferences.getInstance();
      final storedDisp =
          p.getString(AppConfig.prefPreferredExploreDisplayKey)?.trim();
      final v = p.getString(AppConfig.prefPreferredExploreCityKey)?.trim();
      if (!mounted) return;
      if (storedDisp != null && storedDisp.isNotEmpty) {
        setState(() => _preferredExploreCityDisplay = storedDisp);
        return;
      }
      final key = v ?? '';
      final disp = await _resolveExploreCityLabel(
        key.isEmpty ? 'all' : key,
      );
      if (!mounted) return;
      setState(() => _preferredExploreCityDisplay = disp);
    } catch (_) {}
  }

  Future<void> _savePreferredExploreCity(String key, SaudiLocation? loc) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(AppConfig.prefPreferredExploreCityKey, key);
    if (loc != null &&
        loc.lat.abs() > 1e-6 &&
        loc.lng.abs() > 1e-6 &&
        loc.lat.isFinite &&
        loc.lng.isFinite) {
      await p.setDouble(AppConfig.prefPreferredExploreLatKey, loc.lat);
      await p.setDouble(AppConfig.prefPreferredExploreLngKey, loc.lng);
    } else {
      await p.remove(AppConfig.prefPreferredExploreLatKey);
      await p.remove(AppConfig.prefPreferredExploreLngKey);
    }
    final String disp;
    if (loc != null) {
      final gov = _isAr
          ? ((loc.governorateAr ?? '').trim())
          : ((loc.governorateEn ?? '').trim());
      final city = _isAr ? loc.cityAr : loc.cityEn;
      disp = gov.isNotEmpty ? '$gov — $city' : city;
      await p.setString(AppConfig.prefPreferredExploreDisplayKey, disp);
    } else {
      disp = key;
    }
    if (!mounted) return;
    setState(() => _preferredExploreCityDisplay = disp);
  }

  Future<void> _pickExploreCityFromMap() async {
    final res = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => MapPickerPage(
          isAr: _isAr,
          kingdomOverview: true,
          pinTitle:
              _isAr ? 'مدينة الاستكشاف الافتراضية' : 'Default explore city',
          pinSubtitle: _isAr
              ? 'سيتم استخدام أقرب مدينة لهذه النقطة في الرئيسية'
              : 'Home will use the nearest city to this point',
          pinKindLabel: _isAr ? 'استكشاف' : 'Explore',
        ),
      ),
    );
    if (!mounted || res == null) return;
    final lat = (res['lat'] as num?)?.toDouble();
    final lng = (res['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final info = await SaudiLocationsService.instance.findNearest(lat, lng);
    if (!mounted || info == null) return;
    await _savePreferredExploreCity(info.cityEn, info);
  }

  Future<T?> _showSearchablePickSheet<T>({
    required String title,
    required List<T> items,
    required String Function(T) label,
    String Function(T)? subtitle,
  }) async {
    final tc = TextEditingController();
    try {
      return await showModalBottomSheet<T>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            minChildSize: 0.35,
            maxChildSize: 0.92,
            builder: (_, scrollCtrl) {
              return StatefulBuilder(
                builder: (ctx, setModal) {
                  final q = normalizeForListSearch(tc.text);
                  final filtered = items.where((e) {
                    if (q.isEmpty) return true;
                    final hay = normalizeForListSearch(
                      '${label(e)} ${subtitle?.call(e) ?? ''}',
                    );
                    return hay.contains(q);
                  }).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: AqarTextField(
                          controller: tc,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: _isAr ? 'بحث' : 'Search',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.search),
                          ),
                          onChanged: (_) => setModal(() {}),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollCtrl,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final e = filtered[i];
                            final sub = subtitle?.call(e);
                            return ListTile(
                              title: Text(label(e)),
                              subtitle: (sub == null || sub.isEmpty)
                                  ? null
                                  : Text(
                                      sub,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              onTap: () => Navigator.pop(ctx, e),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      );
    } finally {
      tc.dispose();
    }
  }

  Future<void> _pickExploreCityFromHierarchy() async {
    final all = await SaudiLocationsService.instance.loadAll();
    if (!mounted || all.isEmpty) return;

    final byRegion = <String, List<SaudiLocation>>{};
    for (final L in all) {
      final r = _isAr ? L.regionAr : L.regionEn;
      if (r.isEmpty) continue;
      byRegion.putIfAbsent(r, () => []).add(L);
    }
    final regions = byRegion.keys.toList()..sort();

    final region = await _showSearchablePickSheet<String>(
      title: _isAr ? 'اختر المنطقة' : 'Pick region',
      items: regions,
      label: (s) => s,
    );
    if (region == null || !mounted) return;

    final inReg = byRegion[region]!;
    final byGov = <String, List<SaudiLocation>>{};
    for (final L in inReg) {
      final gRaw = _isAr ? L.governorateAr : L.governorateEn;
      final g = (gRaw != null && gRaw.trim().isNotEmpty)
          ? gRaw.trim()
          : (_isAr ? L.cityAr : L.cityEn);
      byGov.putIfAbsent(g, () => []).add(L);
    }
    final govKeys = byGov.keys.toList()..sort();

    final gov = await _showSearchablePickSheet<String>(
      title: _isAr ? 'اختر المحافظة' : 'Pick governorate',
      items: govKeys,
      label: (s) => s,
    );
    if (gov == null || !mounted) return;

    final cities = byGov[gov]!;
    final byEn = <String, SaudiLocation>{};
    for (final L in cities) {
      byEn[L.cityEn] = L;
    }
    final cityList = byEn.values.toList()
      ..sort(
        (a, b) => (_isAr ? a.cityAr : a.cityEn)
            .compareTo(_isAr ? b.cityAr : b.cityEn),
      );

    final pickedLoc = await _showSearchablePickSheet<SaudiLocation>(
      title: _isAr ? 'اختر المدينة' : 'Pick city',
      items: cityList,
      label: (L) => _isAr ? L.cityAr : L.cityEn,
      subtitle: (L) => [
        _isAr ? L.regionAr : L.regionEn,
        _isAr ? (L.governorateAr ?? '').trim() : (L.governorateEn ?? '').trim(),
      ].where((s) => s.isNotEmpty).join(' · '),
    );
    if (pickedLoc == null || !mounted) return;
    await _savePreferredExploreCity(pickedLoc.cityEn, pickedLoc);
  }

  Future<void> _pickPreferredExploreCity() async {
    final mode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.public_outlined),
              title: Text(_isAr ? 'كل المدن' : 'All cities'),
              onTap: () => Navigator.pop(ctx, 'all'),
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: Text(_isAr ? 'تحديد على الخريطة' : 'Pick on map'),
              onTap: () => Navigator.pop(ctx, 'map'),
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(
                _isAr
                    ? 'منطقة ← محافظة ← مدينة'
                    : 'Region → governorate → city',
              ),
              onTap: () => Navigator.pop(ctx, 'list'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || mode == null) return;
    if (mode == 'all') {
      final p = await SharedPreferences.getInstance();
      await p.setString(AppConfig.prefPreferredExploreCityKey, 'all');
      await p.remove(AppConfig.prefPreferredExploreDisplayKey);
      await p.remove(AppConfig.prefPreferredExploreLatKey);
      await p.remove(AppConfig.prefPreferredExploreLngKey);
      if (!mounted) return;
      setState(() {
        _preferredExploreCityDisplay =
            _isAr ? 'الكل — كما في فلتر الرئيسية' : 'All — same as home filter';
      });
      return;
    }
    if (mode == 'map') {
      await _pickExploreCityFromMap();
      return;
    }
    if (mode == 'list') {
      await _pickExploreCityFromHierarchy();
    }
  }

  Widget _browseOrganizationsCard() {
    final t = AppLocalizations.of(context)!;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.apartment_outlined),
        title: Text(t.orgBrowseTitle),
        subtitle: Text(
          _isAr
              ? 'تصفّح المكاتب والمؤسسات وطلب الانضمام'
              : 'Browse offices & institutions and request to join',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Text(_isAr ? 'فتح' : 'Open'),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  BrowseOrganizationsScreen(lang: _isAr ? 'ar' : 'en'),
            ),
          );
        },
      ),
    );
  }

  Widget _exploreCityCard() {
    final subtitle = _preferredExploreCityDisplay.isNotEmpty
        ? _preferredExploreCityDisplay
        : (_isAr ? 'الكل — كما في فلتر الرئيسية' : 'All — same as home filter');

    return Card(
      child: ListTile(
        leading: const Icon(Icons.explore_outlined),
        title: Text(
          _isAr ? 'مدينة الاستكشاف الافتراضية' : 'Default explore city',
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        trailing: Text(_isAr ? 'تغيير' : 'Change'),
        onTap: _pickPreferredExploreCity,
      ),
    );
  }

  Future<void> _loadInAppSoundPref() async {
    await InAppNotificationSoundPrefs.loadFromPrefs();
    if (!mounted) return;
    setState(() => _inAppSoundEnabled = InAppNotificationSoundPrefs.isEnabled);
  }

  Future<void> _loadHapticsPref() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getBool(AppConfig.prefHapticsEnabledKey) ?? true;
      AppHaptics.enabled = v;
      if (!mounted) return;
      setState(() => _hapticsEnabled = v);
    } catch (_) {}
  }

  Future<void> _loadMotionPref() async {
    try {
      final v = await AppMotionPrefs.isEnabled();
      AppMotionPolicy.userEnabled = v;
      if (!mounted) return;
      setState(() => _motionEnabled = v);
    } catch (_) {}
  }

  Future<void> _loadChatNotificationPref() async {
    try {
      final v = await ChatNotificationPrefs.isEnabled();
      if (!mounted) return;
      setState(() => _chatNotificationsEnabled = v);
    } catch (_) {}
  }

  Future<void> _loadChatMessageSoundPref() async {
    await ChatMessageSoundPrefs.loadFromPrefs();
    if (!mounted) return;
    setState(() => _chatMessageSoundEnabled = ChatMessageSoundPrefs.isEnabled);
  }

  Future<void> _loadGraceMinutes() async {
    try {
      final p = await SharedPreferences.getInstance();
      final m = p.getInt(kPrefBgLockGraceMinutes) ??
          kAppBackgroundLockGraceMinutesDefault;
      if (!mounted) return;
      setState(() => _graceMinutes = m.clamp(1, 60));
    } catch (_) {}
  }

  Future<void> _loadDeviceAndAppInfo() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final lines = <String>[];
      final di = DeviceInfoPlugin();
      if (kIsWeb) {
        final w = await di.webBrowserInfo;
        lines.add('${w.browserName.name} — ${w.platform ?? ''}');
        lines.add((w.userAgent ?? '').trim());
      } else {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
            final a = await di.androidInfo;
            lines.add('Android ${a.version.release} (SDK ${a.version.sdkInt})');
            lines.add('${a.manufacturer} ${a.model}');
            lines.add('Device: ${a.id}');
            break;
          case TargetPlatform.iOS:
            final i = await di.iosInfo;
            lines.add('${i.name} — iOS ${i.systemVersion}');
            lines.add('Model: ${i.model}');
            lines.add('Identifier: ${i.identifierForVendor ?? ''}');
            break;
          case TargetPlatform.windows:
            try {
              final w = await di.windowsInfo;
              lines.add(
                '${w.productName} — ${w.displayVersion.trim().isNotEmpty ? w.displayVersion : 'Windows'}',
              );
              lines.add(w.computerName);
            } catch (_) {
              lines.add('Windows');
            }
            break;
          case TargetPlatform.linux:
            try {
              final l = await di.linuxInfo;
              lines.add(l.prettyName);
            } catch (_) {
              lines.add('Linux');
            }
            break;
          case TargetPlatform.macOS:
            try {
              final m = await di.macOsInfo;
              lines.add('${m.computerName} — macOS ${m.osRelease}');
              lines.add('Model: ${m.model}');
            } catch (_) {
              lines.add('macOS');
            }
            break;
          default:
            lines.add(defaultTargetPlatform.name);
        }
      }
      if (!mounted) return;
      setState(() {
        _appVersion = '${pkg.version} (${pkg.buildNumber})';
        _deviceLines = lines;
      });
    } catch (_) {}
  }

  Future<void> _loadPermissionSummary() async {
    try {
      if (kIsWeb) {
        if (!mounted) return;
        setState(() {
          _permissionLines = _isAr
              ? [
                  'الكاميرا: تُطلب عند الاستخدام داخل المتصفح',
                  'الموقع: تُطلب عند الاستخدام داخل المتصفح',
                  'الإشعارات: من إعدادات المتصفح لهذا الموقع',
                  'التخزين المحلي: ضروري للجلسة والأمان',
                ]
              : [
                  'Camera: requested in-browser when needed',
                  'Location: requested in-browser when needed',
                  'Notifications: browser site settings',
                  'Local storage: required for session & security',
                ];
        });
        return;
      }
      final rows = <String>[];
      Future<void> add(Permission p, String label) async {
        final s = await p.status;
        final t = s.isGranted
            ? (_isAr ? 'مسموح' : 'Granted')
            : s.isDenied
                ? (_isAr ? 'مرفوض' : 'Denied')
                : s.isPermanentlyDenied
                    ? (_isAr ? 'مرفوض دائماً' : 'Permanently denied')
                    : s.isLimited
                        ? (_isAr ? 'محدود' : 'Limited')
                        : (_isAr ? 'غير محدد' : 'Unknown');
        rows.add('$label: $t');
      }

      await add(Permission.camera, _isAr ? 'الكاميرا' : 'Camera');
      await add(Permission.photos, _isAr ? 'الصور' : 'Photos');
      await add(Permission.microphone, _isAr ? 'الميكروفون' : 'Microphone');
      await add(Permission.location, _isAr ? 'الموقع' : 'Location');
      await add(Permission.notification, _isAr ? 'الإشعارات' : 'Notifications');

      if (!mounted) return;
      setState(() => _permissionLines = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _permissionLines = [
          _isAr
              ? 'تعذر قراءة حالة الصلاحيات على هذا الجهاز'
              : 'Could not read permission status on this device',
        ];
      });
    }
  }

  Future<void> _loadOrgOwnerFlag() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;
      final svc = OrgTeamService(_sb);
      final row = await _sb
          .from('users_profiles')
          .select('account_type')
          .eq('user_id', uid)
          .maybeSingle();
      final at = (row?['account_type'] ?? '').toString().toLowerCase().trim();
      if (at == 'office' || at == 'institution' || at == 'company') {
        await svc.ensureMyOrgUnit();
      }
      final ctx = await svc.myOrgContext();
      if (!mounted) return;
      setState(() {
        _bumpSettingsContent();
        _orgOwner = ctx != null && ctx['is_owner'] == true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _bumpSettingsContent();
          _orgOwner = false;
        });
      }
    }
  }

  String _pickStr(Map<String, dynamic> row, String k) =>
      (row[k] ?? '').toString().trim();

  String _buildQuadrupleName(Map<String, dynamic> profile, {required bool ar}) {
    final parts = ar
        ? [
            _pickStr(profile, 'first_name_ar'),
            _pickStr(profile, 'second_name_ar'),
            _pickStr(profile, 'third_name_ar'),
            _pickStr(profile, 'fourth_name_ar'),
          ]
        : [
            _pickStr(profile, 'first_name_en'),
            _pickStr(profile, 'second_name_en'),
            _pickStr(profile, 'third_name_en'),
            _pickStr(profile, 'fourth_name_en'),
          ];
    final joined = parts.where((e) => e.isNotEmpty).join(' ');
    if (joined.isNotEmpty) return joined;

    final fullAr = _pickStr(profile, 'full_name_ar');
    final fullEn = _pickStr(profile, 'full_name_en');
    final anyFull = _pickStr(profile, 'full_name');
    final legacy = _pickStr(profile, 'name');

    if (ar) {
      if (fullAr.isNotEmpty) return fullAr;
      if (anyFull.isNotEmpty) return anyFull;
      return legacy;
    }
    if (fullEn.isNotEmpty) return fullEn;
    if (anyFull.isNotEmpty) return anyFull;
    return legacy;
  }

  String _accountCategoryLabel(String raw) {
    final k = raw.trim().toLowerCase();
    switch (k) {
      case 'marketer':
      case 'agent':
      case 'broker':
        return _isAr ? 'مسوّق عقاري' : 'Marketer';
      case 'office':
      case 'agency':
        return _isAr ? 'مكتب عقاري' : 'Real-estate office';
      case 'company':
        return _isAr ? 'شركة عقارية' : 'Real-estate company';
      case 'institution':
        return _isAr ? 'مؤسسة عقارية' : 'Institution';
      case 'individual_seller':
      case 'owner_individual':
      case 'individual':
      case 'owner':
      case 'seller':
        return _isAr ? 'فرد / مالك' : 'Individual / Owner';
      case 'user':
      case 'buyer':
      case 'customer':
        return _isAr ? 'مستخدم' : 'User';
      default:
        if (k.isEmpty) return _isAr ? 'غير محدد' : 'Not set';
        return raw;
    }
  }

  String _resolveAccountCategory(Map<String, dynamic> map) {
    final at = _pickStr(map, 'account_type');
    if (at.isNotEmpty) return _accountCategoryLabel(at);
    final role = _pickStr(map, 'role').toLowerCase();
    if (role == 'marketer' || role == 'agent' || role == 'broker') {
      return _accountCategoryLabel('marketer');
    }
    if (role == 'owner') return _accountCategoryLabel('owner');
    if (role == 'admin') {
      return _isAr ? 'مشرف' : 'Administrator';
    }
    return _accountCategoryLabel('user');
  }

  String _roleLabel() {
    switch (_roleKey) {
      case 'admin':
        return _isAr ? 'مشرف' : 'Administrator';
      case 'agent':
      case 'marketer':
      case 'broker':
        return _isAr ? 'مسوّق عقاري' : 'Marketer';
      case 'owner':
        return _isAr ? 'مالك عقار' : 'Owner';
      default:
        return _isAr ? 'مستخدم' : 'User';
    }
  }

  // =========================
  // LOAD USER
  // =========================
  String _formatProfileDate(dynamic v) {
    if (v == null) return '—';
    final s = v.toString().trim();
    if (s.isEmpty) return '—';
    final dt = DateTime.tryParse(s);
    if (dt != null) {
      final d = dt.toLocal();
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      final ss = d.second.toString().padLeft(2, '0');
      if (_isAr) {
        return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}  $hh:$mm:$ss';
      }
      return '${DateFormat.yMMMd('en').format(d)}  $hh:$mm:$ss';
    }
    return s;
  }

  Future<void> _loadUser() async {
    final u = _sb.auth.currentUser;
    if (u == null) return;

    try {
      Map<String, dynamic>? profile;
      try {
        profile = await _sb
            .from('users_profiles')
            .select(
              'first_name_ar,second_name_ar,third_name_ar,fourth_name_ar,'
              'first_name_en,second_name_en,third_name_en,fourth_name_en,'
              'full_name_ar,full_name_en,full_name,office_name,display_name,'
              'avatar_url,phone,secondary_phone,role,status,created_at,account_type,'
              'unified_national_number,public_name_source,public_phone_source,'
              'publish_presence_on_cards,'
              'public_member_id,chat_last_seen_hidden,username,license_no',
            )
            .eq('user_id', u.id)
            .maybeSingle();
      } catch (_) {
        profile = await _sb
            .from('users_profiles')
            .select(
              'first_name_ar,second_name_ar,third_name_ar,fourth_name_ar,'
              'first_name_en,second_name_en,third_name_en,fourth_name_en,'
              'full_name_ar,full_name_en,full_name,office_name,'
              'avatar_url,phone,role,status,created_at,account_type,unified_national_number,'
              'public_member_id,chat_last_seen_hidden,username,license_no',
            )
            .eq('user_id', u.id)
            .maybeSingle();
      }

      if (!mounted) return;

      if (profile == null) {
        final meta = u.userMetadata;
        final metaName = ProfileGreetingFromRow.displayNameFromAuthMetadata(
              meta == null ? null : Map<String, dynamic>.from(meta),
            ) ??
            '';
        setState(() {
          _bumpSettingsContent();
          _email = u.email ?? '';
          _fullDisplayName = metaName.isNotEmpty
              ? metaName
              : (_email.isNotEmpty ? _email : '—');
          _phone = '—';
          _avatarUrl = '';
          _accountCategory = _isAr
              ? 'لم يُنشأ ملف بعد — أعد المحاولة أو سجّل خروجاً وادخل مجدداً'
              : 'No profile row — retry or re-login';
          _roleKey = 'user';
          _accountStatus = 'active';
          _createdAt = '—';
          _publicMemberId = '';
        });
        return;
      }

      final map = Map<String, dynamic>.from(profile);
      await PublisherIdentityPrefs.instance.reload(profileRow: map);
      final id = PublisherIdentityPrefs.instance;
      final greeted = ProfileGreetingFromRow.displayName(map, isAr: _isAr);
      final built = _buildQuadrupleName(map, ar: _isAr);
      final alias = CompoundDisplayName.normalize(
        _pickStr(map, 'display_name').isNotEmpty
            ? _pickStr(map, 'display_name')
            : id.displayAlias,
      );
      final official = id.officialName(isAr: _isAr);
      final resolvedName = CompoundDisplayName.normalize(
        (greeted != null && greeted.trim().isNotEmpty)
            ? greeted
            : (alias.isNotEmpty
                ? alias
                : (official.isNotEmpty
                    ? official
                    : (built.isNotEmpty ? built : _pickStr(map, 'full_name')))),
      );
      setState(() {
        _bumpSettingsContent();
        _email = u.email ?? '';
        _fullDisplayName =
            resolvedName.isNotEmpty ? resolvedName : (_email.isNotEmpty ? _email : '—');
        _officialName = official;
        _displayAlias = alias;
        _phone = _pickStr(map, 'phone');
        _secondaryPhone = id.secondaryPhone;
        _publicNameSource = id.nameSource;
        _publicPhoneSource = id.phoneSource;
        _publishPresenceOnCards = id.publishPresenceOnCards;
        _missingProfileFields = AccountCompletionService.missingFieldLabels(
          {
            ...map,
            'username': _pickStr(map, 'username'),
          },
          isAr: _isAr,
        );
        _avatarUrl = _pickStr(map, 'avatar_url');

        final atRaw = _pickStr(map, 'account_type');
        _accountTypeRaw = atRaw;
        _accountCategory = _resolveAccountCategory(map);

        final unn = digitsOnly(
          normalizeAsciiDigits(
            _pickStr(map, 'unified_national_number'),
          ),
        );
        _unifiedNationalDisplay =
            unn.length == 10 ? unn : (_isAr ? '— غير مضاف —' : '— not set —');

        _roleKey = _pickStr(map, 'role').isEmpty
            ? 'user'
            : _pickStr(map, 'role').toLowerCase();
        _accountStatus = _pickStr(map, 'status').isEmpty
            ? 'active'
            : _pickStr(map, 'status');
        _createdAt = _formatProfileDate(map['created_at']);
        _publicMemberId = _pickStr(map, 'public_member_id');
        _chatLastSeenHidden = map['chat_last_seen_hidden'] == true;
      });
      _maybePopWhenProfileCompletionDone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bumpSettingsContent();
        _email = u.email ?? '';
        _accountCategory = _isAr ? 'تعذر تحميل الملف' : 'Profile load failed';
        _createdAt = '—';
      });
      debugPrint('settings _loadUser: $e');
    }
  }

  void _maybePopWhenProfileCompletionDone() {
    if (!widget.focusProfileCompletion) return;
    if (_missingProfileFields.isNotEmpty) return;
    if (!mounted) return;
    if (!Navigator.of(context).canPop()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_missingProfileFields.isNotEmpty) return;
      Navigator.of(context).maybePop(true);
    });
  }

  String _maskedDistinguishedNational() {
    final unn = digitsOnly(normalizeAsciiDigits(_unifiedNationalDisplay));
    if (unn.length != 10) {
      return _unifiedNationalDisplay.trim().isEmpty
          ? '—'
          : _unifiedNationalDisplay;
    }
    if (!_unifiedNationalObscured) return unn;
    return '${unn.substring(0, 2)}••••••${unn.substring(8)}';
  }

  Future<void> _copyDistinguishedNational() async {
    final unn = digitsOnly(normalizeAsciiDigits(_unifiedNationalDisplay));
    if (unn.length != 10) return;
    await Clipboard.setData(ClipboardData(text: unn));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_isAr ? 'تم النسخ' : 'Copied')),
    );
  }

  Future<void> _showEditUnifiedNationalDialog() async {
    final existing = digitsOnly(normalizeAsciiDigits(_unifiedNationalDisplay));
    final c = TextEditingController(
      text: existing.length == 10 ? existing : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.settingsEditDistinguishedNumber),
        content: _keyboardAwareDialogBody(
          AqarTextField(
            controller: c,
            keyboardType: TextInputType.text,
            maxLength: 11,
            inputFormatters: [
              ArabicDigitsToLatinFormatter(),
              FilteringTextInputFormatter.allow(
                RegExp(r'[0-9٠-٩۰-۹\u0646]'),
              ),
            ],
            decoration: InputDecoration(
              counterText: '',
              hintText: _isAr ? 'ن700… أو 700…' : '700…',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'حفظ' : 'Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      c.dispose();
      return;
    }
    final d = normalizeUnifiedNationalInput(c.text);
    c.dispose();
    if (!isValidUnifiedNationalNumberDigits(d)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'يجب إدخال 10 أرقام تبدأ بـ 700.'
                : 'Must be 10 digits starting with 700.',
          ),
        ),
      );
      return;
    }
    try {
      await AccountCompletionService.saveUnifiedNational(
        sb: _sb,
        tenDigits700: d,
      );
      if (!mounted) return;
      await _loadUser();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isAr ? 'تم الحفظ' : 'Saved'),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isAr ? 'تعذر الحفظ' : 'Could not save'),
        ),
      );
    }
  }

  // =========================
  // AVATAR
  // =========================
  /// ضغط وتصغير ثم إخراج JPEG موحّد للرفع السريع والعرض.
  Uint8List _compressToAvatarJpeg(Uint8List raw) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      throw Exception('INVALID_IMAGE');
    }

    img.Image work = decoded;
    final w = work.width;
    final h = work.height;
    if (w > _avatarMaxSide || h > _avatarMaxSide) {
      if (w >= h) {
        work = img.copyResize(
          work,
          width: _avatarMaxSide,
          interpolation: img.Interpolation.linear,
        );
      } else {
        work = img.copyResize(
          work,
          height: _avatarMaxSide,
          interpolation: img.Interpolation.linear,
        );
      }
    }

    return Uint8List.fromList(
      img.encodeJpg(work, quality: _avatarJpegQuality),
    );
  }

  Future<Uint8List?> _pickRawImageBytes() async {
    final t0 = AppLocalizations.of(context);
    if (t0 != null) {
      final ok = await RuntimePermissionHelper.ensurePhotos(context, t: t0);
      if (!ok || !mounted) return null;
    }
    if (kIsWeb) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(_isAr ? 'معرض الصور' : 'Photo library'),
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text(_isAr ? 'ملف من الجهاز' : 'File from device'),
                  onTap: () => Navigator.pop(ctx, 'file'),
                ),
              ],
            ),
          );
        },
      );
      if (choice == null || !mounted) return null;

      if (choice == 'file') {
        final r = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
          withData: true,
        );
        if (r == null || r.files.isEmpty) return null;
        final f = r.files.first;
        return f.bytes;
      }

      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      if (x == null) return null;
      return x.readAsBytes();
    }

    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 95,
    );
    if (x == null) return null;
    return x.readAsBytes();
  }

  Future<void> _pickAndUploadAvatar() async {
    final t = AppLocalizations.of(context)!;
    final uid = _sb.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;

    suspendAutoLock.value = true;
    Uint8List? raw;
    try {
      raw = await _pickRawImageBytes();
    } finally {
      suspendAutoLock.value = false;
    }
    if (raw == null || !mounted) return;

    if (raw.length > _avatarMaxInputBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isAr
              ? 'حجم الصورة كبير جداً (الحد الأقصى 12 ميجابايت)'
              : 'Image too large (max 12 MB)'),
        ),
      );
      return;
    }

    setState(() => _uploadingPhoto = true);

    try {
      final jpegBytes = _compressToAvatarJpeg(raw);
      final path = '$_avatarFolder/$uid/avatar.jpg';

      await _sb.storage.from(_avatarStorageBucket).uploadBinary(
            path,
            jpegBytes,
            fileOptions: FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      final publicUrl =
          _sb.storage.from(_avatarStorageBucket).getPublicUrl(path);

      final stamp = DateTime.now().toUtc().toIso8601String();
      try {
        await _sb.from('users_profiles').update({
          'avatar_url': publicUrl,
          'avatar_updated_at': stamp,
        }).eq('user_id', uid);
      } catch (_) {
        // إن لم يُنفَّذ بعد migration العمود avatar_updated_at
        await _sb.from('users_profiles').update({
          'avatar_url': publicUrl,
        }).eq('user_id', uid);
      }

      if (!mounted) return;
      setState(() {
        _bumpSettingsContent();
        _avatarUrl = publicUrl;
        _uploadingPhoto = false;
      });

      _showTempSnack(t.profilePhotoUpdated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingPhoto = false);
      final msg = e.toString().contains('INVALID_IMAGE')
          ? (_isAr ? 'صورة غير صالحة' : 'Invalid image file')
          : '${t.profilePhotoFailed}: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  // =========================
  // FAST LOGIN
  // =========================
  Future<void> _loadFastLogin() async {
    final pin = await FastLoginService.isPinEnabled();
    final can = await FastLoginService.canCheckBiometrics();
    final faceOn = await FastLoginService.isFaceLoginPreferred();
    final fpOn = await FastLoginService.isFingerprintLoginPreferred();
    final faceHw = await FastLoginService.deviceReportsFaceSensor();
    final fpHw = await FastLoginService.deviceReportsFingerprintSensor();
    if (!mounted) return;
    setState(() {
      _pinEnabled = pin;
      _canBio = can;
      _faceOn = faceOn;
      _fpOn = fpOn;
      _faceHw = faceHw;
      _fpHw = fpHw;
    });
  }

  Future<void> _showChangePinDialog() async {
    final t = AppLocalizations.of(context)!;
    final c1 = TextEditingController();
    final c2 = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.changeQuickPin),
          content: _keyboardAwareDialogBody(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AqarTextField(
                  controller: c1,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: t.newPinLabel,
                    counterText: '',
                  ),
                  inputFormatters: [
                    ArabicDigitsToLatinFormatter(),
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                ),
                AqarTextField(
                  controller: c2,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: t.confirmPinLabel,
                    counterText: '',
                  ),
                  inputFormatters: [
                    ArabicDigitsToLatinFormatter(),
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_isAr ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_isAr ? 'حفظ' : 'Save'),
            ),
          ],
        );
      },
    );

    if (ok != true || !mounted) {
      c1.dispose();
      c2.dispose();
      return;
    }

    final p1 = FastLoginService.normalizeDigits(c1.text);
    final p2 = FastLoginService.normalizeDigits(c2.text);
    c1.dispose();
    c2.dispose();

    if (p1.length != 6 || p2.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              _isAr ? 'الرمز يجب أن يكون 6 أرقام' : 'PIN must be 6 digits'),
        ),
      );
      return;
    }
    if (p1 != p2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.pinMismatch)),
      );
      return;
    }

    try {
      await FastLoginService.setPin(p1);
      await FastLoginService.setPinEnabled(true);
      if (!mounted) return;
      setState(() => _pinEnabled = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.pinUpdated)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.changePasswordFailed)),
      );
    }
  }

  // =========================
  // DEVICES
  // =========================
  Future<void> _loadDevices({bool ensureCurrent = true}) async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;

      List<dynamic> data = [];
      try {
        data = await _sb
            .from('user_devices')
            .select(
              'id, device_fingerprint, device_label, city, platform, last_seen, created_at',
            )
            .eq('user_id', uid)
            .order('last_seen', ascending: false);
      } catch (_) {
        try {
          data = await _sb
              .from('user_devices')
              .select(
                'id, device_fingerprint, device_label, last_seen, created_at',
              )
              .eq('user_id', uid)
              .order('last_seen', ascending: false);
        } catch (_) {}
      }

      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(data);
      setState(() => _devices = list);

      if (!ensureCurrent || _sb.auth.currentSession == null) return;
      final key = await UserInstallSessionService.installDeviceKey();
      final has =
          list.any((d) => '${d['device_fingerprint'] ?? ''}'.trim() == key);
      if (has) return;
      final reg =
          await UserInstallSessionService.registerDeviceSlotAfterSignIn();
      if (reg.ok && mounted) {
        await _loadDevices(ensureCurrent: false);
      }
    } catch (_) {}
  }

  // =========================
  // SESSIONS
  // =========================
  Future<void> _loadSessions() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;

      // أعمدة الجدول قد تختلف — نبدأ بأقل أعمدة لتفادي 400.
      List<dynamic> raw = [];
      try {
        raw = await _sb
            .from('login_logs')
            .select('id, created_at')
            .eq('user_id', uid)
            .limit(40);
      } on PostgrestException catch (_) {
        try {
          raw = await _sb
              .from('login_logs')
              .select('id')
              .eq('user_id', uid)
              .limit(40);
        } catch (_) {}
      }
      final list = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      list.sort((a, b) {
        final da = DateTime.tryParse('${a['created_at']}');
        final db = DateTime.tryParse('${b['created_at']}');
        return (db ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(da ?? DateTime.fromMillisecondsSinceEpoch(0));
      });

      if (!mounted) return;
      setState(() => _sessions = list.take(20).toList());
    } catch (_) {}
  }

  // =========================
  // DELETE ACCOUNT
  // =========================
  Future<void> _deleteAccount() async {
    final confirm = await showAppConfirmDialog(
      context: context,
      title: _isAr ? 'حذف الحساب' : 'Delete account',
      message: _isAr
          ? 'هل أنت متأكد؟ سيتم حذف الحساب نهائياً.'
          : 'Are you sure? Your account will be permanently deleted.',
      cancelLabel: _isAr ? 'إلغاء' : 'No',
      confirmLabel: _isAr ? 'حذف' : 'Yes',
      isDanger: true,
    );

    if (!confirm) return;

    try {
      await _sb.rpc('delete_my_account');
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {}
  }

  // =========================
  // LOGOUT DEVICE
  // =========================
  Future<void> _logoutDevice(String id) async {
    try {
      if (!mounted) return;
      _showTempSnack(
        _isAr
            ? 'حذف الجهاز يتطلب تحققاً — سيُربط لاحقاً برسالة نصية/إشعار'
            : 'Device removal needs verification — later linked to SMS/push',
      );
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const DeviceManagementPage(mandatory: false),
        ),
      );
      if (mounted) await _loadDevices(ensureCurrent: false);
    } catch (_) {
      try {
        await _sb.from('user_devices').delete().eq('id', id);
        await _loadDevices(ensureCurrent: false);
        if (mounted) {
          _showTempSnack(
            _isAr ? 'تم حذف الجهاز' : 'Device removed',
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _logoutAllDevices() async {
    try {
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const DeviceManagementPage(mandatory: false),
        ),
      );
      if (mounted) await _loadDevices(ensureCurrent: false);
    } catch (_) {}
  }

  // =========================
  // HELPERS
  // =========================
  String _sessionKindLabel(String? platform, AppLocalizations t) {
    final p = (platform ?? '').toLowerCase().trim();
    if (p.contains('web')) return t.settingsSessionKindWeb;
    if (p == 'android' ||
        p == 'ios' ||
        p.contains('android') ||
        p.contains('iphone')) {
      return t.settingsSessionKindApp;
    }
    if (p.isEmpty) return t.settingsSessionKindUnknown;
    return p;
  }

  Map<String, dynamic>? _tryParseDevicePayload(Map<String, dynamic> d) {
    final raw = '${d['device'] ?? ''}'.trim();
    if (raw.isEmpty || !raw.startsWith('{')) return null;
    try {
      final j = jsonDecode(raw);
      if (j is Map) return Map<String, dynamic>.from(j);
    } catch (_) {}
    return null;
  }

  /// صف user_sessions (عمود device قد يحمل JSON من التطبيق).
  String _userSessionCardTitle(Map<String, dynamic> d) {
    final j = _tryParseDevicePayload(d);
    if (j != null) {
      final label = '${j['label'] ?? ''}'.trim();
      if (label.isNotEmpty) return label;
      final plat = '${j['platform'] ?? ''}'.trim();
      final id = '${j['install_id'] ?? ''}'.trim();
      if (plat.isNotEmpty && id.isNotEmpty) {
        final short = id.length > 8 ? '…${id.substring(id.length - 8)}' : id;
        return '$plat · $short';
      }
      if (plat.isNotEmpty) return plat;
      if (id.isNotEmpty) return id;
    }
    final raw = '${d['device'] ?? ''}'.trim();
    if (raw.length > 64) return '${raw.substring(0, 61)}…';
    if (raw.isNotEmpty) return raw;
    return '—';
  }

  String _userSessionKindLine(Map<String, dynamic> d, AppLocalizations t) {
    final j = _tryParseDevicePayload(d);
    if (j != null) {
      final plat = '${j['platform'] ?? ''}'.trim();
      if (plat.isNotEmpty) return _sessionKindLabel(plat, t);
    }
    return t.settingsSessionKindUnknown;
  }

  /// login_logs أو صفوف قديمة (device_label / user_agent).
  String _deviceRowTitle(Map<String, dynamic> d) {
    final label = '${d['device_label'] ?? ''}'.trim();
    if (label.isNotEmpty) return label;
    final ua = '${d['user_agent'] ?? ''}'.trim();
    if (ua.length > 52) return '${ua.substring(0, 49)}…';
    if (ua.isNotEmpty) return ua;
    final dev = '${d['device'] ?? ''}'.trim();
    if (dev.length > 52) return '${dev.substring(0, 49)}…';
    return dev.isNotEmpty ? dev : '—';
  }

  String _formatSessionTs(dynamic raw) {
    final dt = DateTime.tryParse('${raw ?? ''}');
    if (dt == null) return '—';
    final loc = _isAr ? 'ar' : 'en';
    return DateFormat.yMMMd(loc).add_Hm().format(dt.toLocal());
  }

  /// عنوان قريب من حافة البداية (يمين في العربية) والتفاصيل في المقابل.
  Widget _settingsKvRow({
    required String label,
    required String value,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
              textAlign: TextAlign.start,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: cs.onSurface,
                height: 1.35,
              ),
              textAlign: TextAlign.start,
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // PROFILE CARD
  // =========================
  Widget _profileCompletionCheckCard() {
    final cs = Theme.of(context).colorScheme;
    final missingCount = _missingProfileFields.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isAr ? 'فحص استكمال الملف' : 'Profile completion check',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (missingCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _isAr ? '$missingCount ناقص' : '$missingCount missing',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: cs.onErrorContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _isAr
                  ? 'افتح شاشة الفحص لعرض النواقص واستكمالها أو إعادة الفحص في أي وقت.'
                  : 'Open the check screen to see missing fields, complete them, or recheck anytime.',
              style: TextStyle(
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () async {
                final lang = _isAr ? 'ar' : 'en';
                final done = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    settings: const RouteSettings(name: '/profileEnrollmentCheck'),
                    builder: (_) => ProfileEnrollmentGateScreen(
                      lang: lang,
                      embeddedInSettings: true,
                      onRecheck: () async {
                        await _loadUser();
                      },
                    ),
                  ),
                );
                await _loadUser();
                if (!mounted) return;
                if (done == true || _missingProfileFields.isEmpty) {
                  _showTempSnack(
                    _isAr
                        ? 'الملف مكتمل أو تم التحديث'
                        : 'Profile complete or updated',
                  );
                }
              },
              child: Text(
                _isAr ? 'فتح فحص الاستكمال' : 'Open completion check',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileCard() {
    final t = AppLocalizations.of(context)!;
    final displayName =
        _fullDisplayName.isNotEmpty ? _fullDisplayName : (_isAr ? '—' : '—');

    return Card(
      child: Column(
        children: [
          const SizedBox(height: 16),
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 44,
                backgroundImage:
                    _avatarUrl.isEmpty ? null : NetworkImage(_avatarUrl),
                child: _avatarUrl.isEmpty
                    ? const Icon(Icons.person, size: 44)
                    : null,
              ),
              if (_uploadingPhoto)
                Positioned.fill(
                  child: Center(
                    child: AppLogoLoading(
                      size: 56,
                      compact: true,
                    ),
                  ),
                ),
              Positioned(
                bottom: -4,
                right: _isAr ? null : -4,
                left: _isAr ? -4 : null,
                child: Material(
                  color: Theme.of(context).colorScheme.primary,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.camera_alt_rounded,
                        color: Colors.white, size: 20),
                    tooltip: t.profileChangePhoto,
                    onPressed: _uploadingPhoto ? null : _pickAndUploadAvatar,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              displayName,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _email,
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const Divider(height: 28),
          KeyedSubtree(
            key: _profileCompletionKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_missingProfileFields.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Material(
                      color: Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _isAr
                                  ? 'بيانات ناقصة أو تحتاج تحديثاً'
                                  : 'Missing or outdated data',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ..._missingProfileFields.map(
                              (m) => Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '• $m',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                _profileFactRow(
                  label: _isAr ? 'الاسم / الصفة المعتمدة' : 'Official registered name',
                  value: _officialName.isEmpty ? '—' : _officialName,
                ),
                _profileFactRow(
                  label: _isAr ? 'اسم الظهور المستعار' : 'Display alias',
                  value: _displayAlias.isEmpty
                      ? (_isAr ? '— غير مضبوط —' : '— not set —')
                      : _displayAlias,
                  onEdit: _showEditDisplayNameDialog,
                ),
                _profileFactRow(
                  label: t.accountCategoryLabel,
                  value: _accountCategory,
                ),
                _profileFactRow(
                  label: t.permissionRoleLabel,
                  value: _roleLabel(),
                ),
                _profileFactRow(
                  label: _isAr ? 'الجوال الأساسي' : 'Primary phone',
                  value: _phone.isEmpty ? '—' : _phone,
                  editLabel: _phone.isEmpty
                      ? (_isAr ? 'إضافة' : 'Add')
                      : null,
                  onEdit: digitsOnly(normalizeAsciiDigits(_phone)).length >= 10
                      ? null
                      : _showEditPhoneDialog,
                ),
                _profileFactRow(
                  label: _isAr ? 'الجوال الإضافي' : 'Extra phone',
                  value: _secondaryPhone.isEmpty
                      ? (_isAr ? '— غير مضاف —' : '— not set —')
                      : _secondaryPhone,
                  onEdit: _showEditPhoneDialog,
                  editLabel: _secondaryPhone.isEmpty
                      ? (_isAr ? 'إضافة' : 'Add')
                      : (_isAr ? 'تعديل' : 'Edit'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: PublisherIdentityOptionsCard(
                    isAr: _isAr,
                    nameSource: _publicNameSource,
                    phoneSource: _publicPhoneSource,
                    publishPresence: _publishPresenceOnCards,
                    officialName: _officialName,
                    displayAlias: _displayAlias,
                    primaryPhone: _phone,
                    secondaryPhone: _secondaryPhone,
                    onNameSourceChanged: (v) async {
                      await PublisherIdentityPrefs.instance.setNameSource(v);
                      if (!mounted) return;
                      setState(() {
                        _bumpSettingsContent();
                        _publicNameSource = v;
                      });
                      await _loadUser();
                      _showTempSnack(
                        _isAr
                            ? 'تم تحديث اسم الظهور للآخرين'
                            : 'Public name preference updated',
                      );
                    },
                    onPhoneSourceChanged: (v) async {
                      await PublisherIdentityPrefs.instance.setPhoneSource(v);
                      if (!mounted) return;
                      setState(() {
                        _bumpSettingsContent();
                        _publicPhoneSource = v;
                      });
                      _showTempSnack(
                        _isAr
                            ? 'تم تحديث رقم الجوال الظاهر'
                            : 'Public phone preference updated',
                      );
                    },
                    onPublishPresenceChanged: (v) async {
                      await PublisherIdentityPrefs.instance
                          .setPublishPresenceOnCards(v);
                      if (!mounted) return;
                      setState(() {
                        _bumpSettingsContent();
                        _publishPresenceOnCards = v;
                      });
                      _showTempSnack(
                        _isAr
                            ? 'تم تحديث إظهار الحضور على البطاقات'
                            : 'Card presence preference updated',
                      );
                    },
                  ),
                ),
                _profileFactRow(
                  label: _isAr ? 'حالة الحساب' : 'Account status',
                  value: _accountStatusLabel(_accountStatus),
                ),
                _profileFactRow(
                  label: _isAr ? 'تاريخ الإنشاء' : 'Created at',
                  value: _createdAt.isEmpty ? '—' : _createdAt,
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(Icons.flag_outlined,
                color: Theme.of(context).colorScheme.outline),
            title: Text(t.settingsReportsActivityTitle),
            subtitle: Text(
              t.settingsReportsActivitySubtitle(
                _reportCountProperties,
                _reportCountRequests,
                _reportCountLast30d,
              ),
            ),
          ),
          if (_publicMemberId.isNotEmpty)
            ListTile(
              title: SelectableText(
                _publicMemberId,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              subtitle: Text(t.settingsPublicMemberIdSubtitle),
            ),
          if (AccountCompletionService.accountTypeNeedsUnifiedNational(
            _accountTypeRaw,
          )) ...[
            ListTile(
              title: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _maskedDistinguishedNational(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _unifiedNationalObscured
                        ? t.settingsRevealDistinguishedNumber
                        : t.settingsHideDistinguishedNumber,
                    icon: Icon(
                      _unifiedNationalObscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(() =>
                          _unifiedNationalObscured = !_unifiedNationalObscured);
                    },
                  ),
                  IconButton(
                    tooltip: t.settingsCopyDistinguishedNumber,
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: _copyDistinguishedNational,
                  ),
                ],
              ),
              subtitle: Text(t.settingsDistinguishedNumberSubtitle),
              trailing: Text(
                t.settingsEditDistinguishedNumber,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: _showEditUnifiedNationalDialog,
            ),
            SwitchListTile(
              value: _chatLastSeenHidden,
              onChanged: (v) async {
                await OrgTeamService(_sb).setChatLastSeenHidden(v);
                if (mounted) setState(() => _chatLastSeenHidden = v);
              },
              title: Text(t.settingsLastSeenPrivacyTitle),
              subtitle: Text(t.settingsLastSeenPrivacySubtitle),
            ),
            const Divider(height: 1),
            KeyedSubtree(
              key: _presenceDisplayKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      _isAr
                          ? 'عرض الظهور على البطاقات'
                          : 'Presence on cards',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      _isAr
                          ? 'تحكم بما تراه أنت من «متصل الآن / آخر ظهور» على بطاقات الإعلانات والطلبات والدردشة. يمكنك إخفاء العرض مؤقتاً حتى وقت محدد.'
                          : 'Control what you see for online/last-seen on listing cards, request cards, and chat. You can hide it temporarily until a chosen time.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    value: _presenceShowListing,
                    onChanged: !_presencePrefsLoaded
                        ? null
                        : (v) async {
                            await PresenceDisplayPrefs.instance
                                .setShowOnListingCards(v);
                            if (mounted) {
                              setState(() => _presenceShowListing = v);
                            }
                          },
                    title: Text(
                      _isAr
                          ? 'على بطاقات الإعلانات'
                          : 'On listing cards',
                    ),
                  ),
                  SwitchListTile(
                    value: _presenceShowRequest,
                    onChanged: !_presencePrefsLoaded
                        ? null
                        : (v) async {
                            await PresenceDisplayPrefs.instance
                                .setShowOnRequestCards(v);
                            if (mounted) {
                              setState(() => _presenceShowRequest = v);
                            }
                          },
                    title: Text(
                      _isAr
                          ? 'على بطاقات الطلبات العقارية'
                          : 'On request cards',
                    ),
                  ),
                  SwitchListTile(
                    value: _presenceShowChat,
                    onChanged: !_presencePrefsLoaded
                        ? null
                        : (v) async {
                            await PresenceDisplayPrefs.instance
                                .setShowOnChat(v);
                            if (mounted) {
                              setState(() => _presenceShowChat = v);
                            }
                          },
                    title: Text(
                      _isAr ? 'في الدردشة' : 'In chat',
                    ),
                  ),
                  ListTile(
                    title: Text(
                      _isAr
                          ? 'إخفاء مؤقت حتى تاريخ/وقت'
                          : 'Hide temporarily until',
                    ),
                    subtitle: Text(
                      _presenceHideUntil == null
                          ? (_isAr ? 'غير مفعّل' : 'Off')
                          : DateFormat.yMMMd(_isAr ? 'ar' : 'en')
                              .add_Hm()
                              .format(_presenceHideUntil!.toLocal()),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_presenceHideUntil != null)
                          TextButton(
                            onPressed: () async {
                              await PresenceDisplayPrefs.instance
                                  .clearTemporaryHide();
                              if (mounted) {
                                setState(() => _presenceHideUntil = null);
                              }
                            },
                            child: Text(_isAr ? 'إلغاء' : 'Clear'),
                          ),
                        IconButton(
                          tooltip: _isAr ? 'اختيار وقت' : 'Pick time',
                          onPressed: _pickPresenceHideUntil,
                          icon: const Icon(Icons.schedule_rounded),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          ListTile(
            title: Text(t.profileChangePhoto),
            trailing: Text(_isAr ? 'تغيير' : 'Change',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700)),
            onTap: _uploadingPhoto ? null : _pickAndUploadAvatar,
          ),
          ListTile(
            title: Text(t.changePasswordTitle),
            trailing: Text(_isAr ? 'فتح' : 'Open',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700)),
            onTap: () => Navigator.pushNamed(context, '/changePassword'),
          ),
          ListTile(
            title: Text(t.supportLabel),
            subtitle: Text(
              _isAr
                  ? 'الدعم الفني واستقبال الشكاوى — من قسم الامتثال في الإعدادات أيضاً.'
                  : 'Support & complaints — also under Settings → Compliance.',
            ),
            trailing: Text(_isAr ? 'فتح' : 'Open',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700)),
            onTap: () {
              final uid = _sb.auth.currentUser?.id ?? '';
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => SupportPage(
                    userId: uid,
                    isAr: _isAr,
                    bankColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // =========================
  // SECURITY (PIN على كل المنصات؛ البصمة للجوال فقط)
  // =========================
  Widget _securityCard() {
    final t = AppLocalizations.of(context)!;
    if (!_isMobile) {
      return Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                _isAr ? 'الأمان وقفل الجلسة' : 'Security & session lock',
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _isAr
                    ? 'فعّل رمز PIN لإعادة فتح الجلسة بعد انقضاء المهلة دون إعادة إدخال اسم المستخدم. البصمة متاحة على تطبيق الجوال فقط.'
                    : 'Enable a PIN to unlock after idle timeout without re-entering your username. Biometrics are available on the mobile app only.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SwitchListTile(
              value: _pinEnabled,
              onChanged: (v) async {
                if (v) {
                  await _showChangePinDialog();
                } else {
                  await FastLoginService.setPinEnabled(false);
                }
                if (!mounted) return;
                await _loadFastLogin();
              },
              title: Text(_isAr ? 'رمز الدخول السريع (PIN)' : 'Quick PIN'),
            ),
            if (_pinEnabled)
              ListTile(
                title: Text(t.changeQuickPin),
                trailing: Text(
                  _isAr ? 'تعديل' : 'Change',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: _showChangePinDialog,
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    }
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              _isAr ? 'الأمان والدخول السريع' : 'Security & quick unlock',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          SwitchListTile(
            title: Text(_isAr ? 'تفعيل التعرف على الوجه' : 'Face unlock'),
            subtitle: Text(
              _faceHw
                  ? (_isAr ? 'متاح على هذا الجهاز' : 'Available on this device')
                  : (_isAr
                      ? 'غير متاح على هذا الجهاز'
                      : 'Not available on this device'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            value: _faceOn,
            onChanged: (!_canBio || !_faceHw)
                ? null
                : (v) async {
                    await FastLoginService.setFaceLoginEnabled(v);
                    await _loadFastLogin();
                  },
          ),
          SwitchListTile(
            title: Text(_isAr ? 'تفعيل بصمة الإصبع' : 'Fingerprint unlock'),
            subtitle: Text(
              _fpHw
                  ? (_isAr ? 'متاح على هذا الجهاز' : 'Available on this device')
                  : (_isAr
                      ? 'غير متاح على هذا الجهاز'
                      : 'Not available on this device'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            value: _fpOn,
            onChanged: (!_canBio || !_fpHw)
                ? null
                : (v) async {
                    await FastLoginService.setFingerprintLoginEnabled(v);
                    await _loadFastLogin();
                  },
          ),
          SwitchListTile(
            value: _pinEnabled,
            onChanged: (v) async {
              await FastLoginService.setPinEnabled(v);
              if (!mounted) return;
              setState(() => _pinEnabled = v);
              await _loadFastLogin();
            },
            title: Text(_isAr ? 'رمز الدخول السريع (PIN)' : 'Quick PIN'),
          ),
          if (_pinEnabled)
            ListTile(
              title: Text(t.changeQuickPin),
              trailing: Text(_isAr ? 'تعديل' : 'Change',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700)),
              onTap: _showChangePinDialog,
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              _isAr
                  ? 'مدة بقاء الجلسة بعد إرسال التطبيق للخلفية قبل طلب القفل (دقائق)'
                  : 'Session stays unlocked after app goes to background (minutes)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _isAr
                  ? 'القيمة الافتراضية 15 دقيقة. تُستخدم عند إرسال التطبيق للخلفية مع تفعيل الدخول السريع أو البصمة.'
                  : 'Default is 15 minutes. Used after backgrounding when PIN or biometrics lock is enabled.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Slider(
            value: _graceMinutes.toDouble(),
            min: 1,
            max: 30,
            divisions: 29,
            label: '$_graceMinutes',
            onChanged: (v) async {
              final m = v.round();
              await setAppBackgroundLockGraceMinutes(m);
              if (!mounted) return;
              setState(() => _graceMinutes = m);
            },
          ),
        ],
      ),
    );
  }

  Widget _deviceInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isAr ? 'التطبيق والجهاز' : 'App & device',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            if (_appVersion.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _isAr
                    ? 'إصدار التطبيق: $_appVersion'
                    : 'App version: $_appVersion',
              ),
            ],
            for (final line in _deviceLines) ...[
              const SizedBox(height: 6),
              SelectableText(line),
            ],
            if (_deviceLines.isEmpty && _appVersion.isEmpty)
              Text(_isAr ? 'جارٍ التحميل…' : 'Loading…'),
          ],
        ),
      ),
    );
  }

  Widget _permissionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isAr ? 'حالة الصلاحيات' : 'Permission status',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              _isAr
                  ? 'تظهر الحالة كما يراها النظام. يمكن فتح إعدادات النظام لتعديلها.'
                  : 'Status as reported by the system. Open system settings to change.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            for (final line in _permissionLines) ...[
              SelectableText(line),
              const SizedBox(height: 6),
            ],
            if (_permissionLines.isEmpty)
              Text(_isAr ? 'جارٍ التحميل…' : 'Loading…'),
            TextButton(
              onPressed: () async {
                if (kIsWeb) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      content: Text(
                        _isAr
                            ? 'على الويب: افتح قفل الموقع بجانب شريط العنوان ← أذونات الموقع.'
                            : 'On web: open the site lock next to the address bar → site permissions.',
                      ),
                    ),
                  );
                  return;
                }
                try {
                  final opened = await openAppSettings();
                  if (!opened) {
                    await AppSettings.openAppSettings();
                  }
                } catch (_) {
                  try {
                    await AppSettings.openAppSettings();
                  } catch (_) {}
                }
              },
              child:
                  Text(_isAr ? 'فتح إعدادات النظام' : 'Open system settings'),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // DEVICES
  // =========================
  Widget _devicesCard() {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<String>(
      future: UserInstallSessionService.installDeviceKey(),
      builder: (context, snap) {
        final currentFp = snap.data ?? '';
        if (_devices.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.devices_other_rounded, color: cs.primary, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    _isAr ? 'لا توجد أجهزة مسجلة' : 'No registered devices',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isAr
                        ? 'يُسجَّل هذا الجهاز تلقائياً عند الدخول. اسحب للتحديث أو افتح إدارة الأجهزة.'
                        : 'This device is registered on sign-in. Pull to refresh or open device management.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _loadDevices(),
                    child: Text(_isAr ? 'تحديث' : 'Refresh'),
                  ),
                ],
              ),
            ),
          );
        }

        IconData iconFor(String? platform) {
          final p = (platform ?? '').toLowerCase();
          if (p.contains('web')) return Icons.language_rounded;
          if (p.contains('android')) return Icons.android_rounded;
          if (p.contains('ios') || p.contains('iphone')) {
            return Icons.phone_iphone_rounded;
          }
          if (p.contains('windows') || p.contains('mac') || p.contains('linux')) {
            return Icons.desktop_windows_rounded;
          }
          return Icons.smartphone_rounded;
        }

        Widget kv({
          required String label,
          required String value,
          VoidCallback? onCopy,
        }) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onCopy != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: onCopy,
                    icon: Icon(Icons.copy_rounded, size: 18, color: cs.primary),
                    tooltip: _isAr ? 'نسخ' : 'Copy',
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            ..._devices.map((d) {
              final fp = '${d['device_fingerprint'] ?? ''}'.trim();
              final isCurrent = currentFp.isNotEmpty && fp == currentFp;
              final labelRaw = '${d['device_label'] ?? ''}'.trim();
              final platform = '${d['platform'] ?? ''}'.trim();
              final title = labelRaw.isNotEmpty
                  ? labelRaw
                  : DeviceDisplayLabels.platform(platform, isAr: _isAr);
              final city = '${d['city'] ?? ''}'.trim();
              final first = _formatSessionTs(d['created_at']);
              final last = _formatSessionTs(d['last_seen'] ?? d['created_at']);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: isCurrent
                        ? cs.primary.withValues(alpha: 0.45)
                        : cs.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: cs.primary.withValues(alpha: 0.12),
                            child: Icon(iconFor(platform), color: cs.primary, size: 28),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(height: 4),
                            Text(
                              DeviceDisplayLabels.currentInstallHint(isAr: _isAr),
                              style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.35)),
                    kv(
                      label: _isAr ? 'اسم الطراز' : 'Model name',
                      value: title,
                      onCopy: () {
                        Clipboard.setData(ClipboardData(text: title));
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(milliseconds: 1200),
                            content: Text(_isAr ? 'تم النسخ' : 'Copied'),
                          ),
                        );
                      },
                    ),
                    Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
                    kv(
                      label: _isAr ? 'المنصة' : 'Platform',
                      value: DeviceDisplayLabels.platform(platform, isAr: _isAr),
                    ),
                    Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
                    kv(
                      label: _isAr ? 'أول تسجيل دخول' : 'First sign-in',
                      value: first,
                    ),
                    Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
                    kv(
                      label: _isAr ? 'آخر نشاط' : 'Last activity',
                      value: last,
                    ),
                    Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
                    kv(
                      label: _isAr ? 'الموقع' : 'Location',
                      value: city.isEmpty
                          ? (_isAr ? 'غير محدد' : 'Not set')
                          : city,
                    ),
                    if (!isCurrent)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: () => _logoutDevice('${d['id']}'),
                          child: Text(
                            _isAr ? 'إزالة الجهاز' : 'Remove device',
                            style: TextStyle(color: cs.error, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                t.settingsDevicesFooterHint,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
            FilledButton.tonal(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const DeviceManagementPage(mandatory: false),
                  ),
                ).then((_) {
                  if (mounted) unawaited(_loadDevices(ensureCurrent: false));
                });
              },
              child: Text(
                _isAr ? 'إدارة الأجهزة والحدّ الأقصى' : 'Manage devices & limit',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );
  }

  // =========================
  // ACCOUNT HUB (switch account + replay tour)
  // =========================
  Widget _accountHubCard() {
    final t = AppLocalizations.of(context)!;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.slideshow_outlined),
            title: Text(t.settingsReplayDashboardTourTitle),
            subtitle: Text(t.settingsReplayDashboardTourSubtitle),
            onTap: () async {
              await DeviceFirstRunPrefs.requestDashboardTourReplay();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.settingsReplayDashboardTourSnackbar)),
              );
              Navigator.of(context).maybePop();
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.switch_account_outlined),
            title: Text(t.settingsOpenSwitchAccountTitle),
            subtitle: Text(t.settingsOpenSwitchAccountSubtitle),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const SwitchAccountScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // =========================
  // SESSIONS
  // =========================
  Widget _sessionsCard() {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(Icons.history_rounded, color: cs.primary),
        title: Text(t.settingsOpenSessionHistoryTitle),
        subtitle: Text(t.settingsOpenSessionHistorySubtitle),
        trailing: const Icon(Icons.open_in_new_rounded),
        onTap: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const SessionHistoryScreen(),
            ),
          );
        },
      ),
    );
  }

  // =========================
  // NOTIFICATIONS (in-app chat alerts from FCM foreground)
  // =========================
  Widget _notificationsCard() {
    final t = AppLocalizations.of(context)!;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: Text(t.settingsInAppNotificationSoundTitle),
            subtitle: Text(
              t.settingsInAppNotificationSoundSubtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            value: _inAppSoundEnabled,
            onChanged: (v) async {
              await InAppNotificationSoundPrefs.setEnabled(v);
              if (!mounted) return;
              setState(() => _inAppSoundEnabled = v);
              _showTempSnack(
                v
                    ? (_isAr
                        ? 'تم تفعيل صوت التنبيهات داخل التطبيق (مؤقتاً حتى ربط الرسائل)'
                        : 'In-app alert sound enabled (temporary until SMS/push link)')
                    : (_isAr
                        ? 'تم إيقاف صوت التنبيهات داخل التطبيق'
                        : 'In-app alert sound disabled'),
              );
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: Text(t.settingsChatMessageSoundTitle),
            subtitle: Text(
              t.settingsChatMessageSoundSubtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            value: _chatMessageSoundEnabled,
            onChanged: (v) async {
              await ChatMessageSoundPrefs.setEnabled(v);
              if (!mounted) return;
              setState(() => _chatMessageSoundEnabled = v);
              _showTempSnack(
                v
                    ? (_isAr
                        ? 'تم تفعيل صوت رسائل الدردشة (إعداد مؤقت)'
                        : 'Chat message sound enabled (temporary setting)')
                    : (_isAr
                        ? 'تم إيقاف صوت رسائل الدردشة'
                        : 'Chat message sound disabled'),
              );
            },
          ),
          if (_isMobile)
            SwitchListTile(
              secondary: const Icon(Icons.chat_outlined),
              title: Text(
                _isAr ? 'تنبيهات رسائل الدردشة' : 'Chat message alerts',
              ),
              subtitle: Text(
                _isAr
                    ? 'إعداد مؤقت — سيُربط لاحقاً بالرسائل النصية/الإشعارات. عند وصول رسالة أثناء استخدام التطبيق.'
                    : 'Temporary setting — later linked to SMS/push. When a message arrives while the app is open.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              value: _chatNotificationsEnabled,
              onChanged: (v) async {
                await ChatNotificationPrefs.setEnabled(v);
                if (!mounted) return;
                setState(() => _chatNotificationsEnabled = v);
                _showTempSnack(
                  v
                      ? (_isAr
                          ? 'تم تفعيل تنبيهات الدردشة مؤقتاً'
                          : 'Chat alerts enabled temporarily')
                      : (_isAr
                          ? 'تم إيقاف تنبيهات الدردشة'
                          : 'Chat alerts disabled'),
                );
              },
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                _isAr
                    ? 'تنبيهات الدردشة والرسائل النصية على الويب مؤقتة حالياً؛ راجع إعدادات المتصفح. الربط الكامل بالرسائل قادم.'
                    : 'Web chat/SMS alerts are temporary for now; check browser settings. Full SMS linking is coming.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }

  // =========================
  // PREFERENCES
  // =========================
  Widget _preferencesCard() {
    final t = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldGroupFrame(
          title: t.settingsAppearanceLanguageSection,
          subtitle: t.settingsAppearanceHubSubtitle,
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
          child: Column(
            children: [
              ListTile(
                title: Text(t.language),
                trailing: DropdownButton<String>(
                  value: langNotifier.value == 'en' ? 'en' : 'ar',
                  items: [
                    DropdownMenuItem(
                        value: 'ar', child: Text(t.languageArabic)),
                    DropdownMenuItem(
                        value: 'en', child: Text(t.languageEnglish)),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    await setAppLang(v);
                    if (!mounted) return;
                    await _loadUser();
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.cloud_sync_outlined),
                title: Text(
                  _isAr
                      ? 'ربط اللغة بهذا الحساب'
                      : 'Save language for this account',
                ),
                subtitle: Text(
                  _isAr
                      ? 'عند التفعيل تُحفظ لغة الواجهة مع المستخدم عند تسجيل الدخول من أجهزة أخرى.'
                      : 'When on, UI language is stored per account for sign-in on other devices.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                value: _syncLangWithAccount,
                onChanged: (v) async {
                  await UserAppearanceSession.writeSyncLangWithAccount(v);
                  await syncSessionAppearanceNotifiers?.call();
                  if (!mounted) return;
                  setState(() => _syncLangWithAccount = v);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.palette_outlined),
                title: Text(
                  _isAr
                      ? 'ربط الثيم بهذا الحساب'
                      : 'Save theme for this account',
                ),
                subtitle: Text(
                  _isAr
                      ? 'عند التفعيل يُحفظ الوضع الفاتح/الداكن مع المستخدم عند الدخول من أجهزة أخرى.'
                      : 'When on, light/dark mode is stored per account for sign-in on other devices.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                value: _syncThemeWithAccount,
                onChanged: (v) async {
                  await UserAppearanceSession.writeSyncThemeWithAccount(v);
                  await syncSessionAppearanceNotifiers?.call();
                  if (!mounted) return;
                  setState(() => _syncThemeWithAccount = v);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.dark_mode_outlined),
                title: Text(t.themeDark),
                subtitle: Text(
                  t.settingsDarkModeSubtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                value: themeModeNotifier.value == ThemeMode.dark,
                onChanged: (v) async {
                  await setAppTheme(v ? ThemeMode.dark : ThemeMode.light);
                  if (!mounted) return;
                  setState(() {});
                },
              ),
              ValueListenableBuilder<Color>(
                valueListenable: accentSeedNotifier,
                builder: (context, accent, _) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          leading: const Icon(Icons.palette_outlined),
                          title: Text(t.settingsAccentTitle),
                          subtitle: Text(
                            t.settingsAccentSubtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final w = constraints.maxWidth;
                              final cols = w < 280
                                  ? 3
                                  : (w < 360 ? 4 : (w < 480 ? 5 : 6));
                              final gap = 10.0;
                              final cell = (w - gap * (cols - 1)) / cols;
                              final size = cell.clamp(32.0, 40.0);
                              return Wrap(
                                spacing: gap,
                                runSpacing: gap,
                                alignment: WrapAlignment.start,
                                children: List.generate(
                                    AppConfig.primaryAccentCount, (i) {
                                  final seed = AppConfig.accentSeedAt(i);
                                  final selected = seed == accent;
                                  return InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () => setAppAccentIndex(i),
                                    child: Ink(
                                      width: size,
                                      height: size,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: seed,
                                        border: Border.all(
                                          width: selected ? 3 : 1,
                                          color: selected
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                              : Colors.black
                                                  .withValues(alpha: 0.12),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              ValueListenableBuilder<double>(
                valueListenable: textScaleNotifier,
                builder: (context, scale, _) {
                  final cs = Theme.of(context).colorScheme;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          leading: const Icon(Icons.format_size_rounded),
                          title: Text(t.settingsTextScaleTitle),
                          subtitle: Text(
                            t.settingsTextScaleSubtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Slider(
                          value: scale.clamp(
                            AppConfig.textScaleMin,
                            AppConfig.textScaleMax,
                          ),
                          min: AppConfig.textScaleMin,
                          max: AppConfig.textScaleMax,
                          divisions: 11,
                          label: t.settingsTextScalePercent(
                            (scale * 100).round(),
                          ),
                          onChanged: (v) {
                            setAppTextScaleFactor(v);
                          },
                        ),
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: 8,
                            end: 8,
                            bottom: 4,
                          ),
                          child: Row(
                            children: [
                              Text(
                                t.settingsTextScalePercent(
                                  (AppConfig.textScaleMin * 100).round(),
                                ),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                t.settingsTextScalePercent(
                                  (AppConfig.textScaleMax * 100).round(),
                                ),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            onPressed: () => setAppTextScaleFactor(1.0),
                            child: Text(t.settingsTextScaleReset),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.schedule_outlined),
                title: Text(
                  _isAr
                      ? 'منطقة عرض تواريخ الإعلانات'
                      : 'Listing date time zone',
                ),
                subtitle: Text(
                  _isAr
                      ? 'يُحفظ على الجهاز ويُستخدم تدريجياً في البطاقات والتفاصيل.'
                      : 'Saved on device; used gradually in cards and details.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                trailing: Icon(Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.outline),
                onTap: _pickListingDateZone,
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                    start: 56, end: 16, bottom: 8),
                child: Text(
                  _isAr
                      ? ListingDateDisplay.zoneLabelAr(_listingDateZone)
                      : ListingDateDisplay.zoneLabelEn(_listingDateZone),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isMobile) ...[
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.vibration),
              title: Text(t.settingsHapticsTitle),
              subtitle: Text(
                t.settingsHapticsSubtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              value: _hapticsEnabled,
              onChanged: (v) async {
                await setAppHapticsEnabled(v);
                if (!mounted) return;
                setState(() => _hapticsEnabled = v);
                if (v) AppHaptics.light();
              },
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.animation_rounded),
            title: Text(
              _isAr ? 'حركات التنقل الخفيفة' : 'Light navigation motion',
            ),
            subtitle: Text(
              _isAr
                  ? 'تكبير أيقونة التبويب المحدد وانتقالات أسلس. يمكن إيقافها للسرعة القصوى.'
                  : 'Subtle selected-tab scale and smoother transitions. Turn off for maximum speed.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            value: _motionEnabled,
            onChanged: (v) async {
              await AppMotionPolicy.setEnabled(v);
              if (!mounted) return;
              setState(() => _motionEnabled = v);
            },
          ),
        ),
      ],
    );
  }

  // =========================
  // DANGER ZONE
  // =========================
  Widget _dangerZone(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.errorContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.error.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.delete_forever_rounded, color: cs.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isAr ? 'حذف الحساب نهائياً' : 'Permanently delete account',
                    style: TextStyle(
                      color: cs.error,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _isAr
                  ? 'لا يمكن التراجع. ستُحذف بياناتك المرتبطة بالحساب وفق سياسة الاحتفاظ.'
                  : 'This cannot be undone. Account-linked data is removed per retention policy.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  foregroundColor: cs.error,
                ),
                onPressed: _deleteAccount,
                child: Text(
                  _isAr ? 'متابعة حذف الحساب' : 'Continue to delete',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gesturesCard() {
    final cs = Theme.of(context).colorScheme;
    final supportsTouch = AppGesturePreferences.supportsTouchBack;
    final supportsKeyboard = AppGesturePreferences.supportsKeyboardBack;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.swipe_rounded),
            title: Text(_isAr ? 'إيماءات التنقل' : 'Navigation gestures'),
            subtitle: Text(
              _isAr
                  ? 'تحكّم بطرق الرجوع السريعة حسب الجهاز المستخدم.'
                  : 'Control quick back navigation options for this device.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          if (supportsTouch) ...[
            SwitchListTile(
              secondary: const Icon(Icons.swipe_left_alt_outlined),
              title: Text(
                _isAr
                    ? 'الرجوع بالسحب يميناً أو يساراً'
                    : 'Swipe left or right to go back',
              ),
              subtitle: Text(
                _isAr
                    ? 'يعمل داخل صفحات التطبيق المفتوحة فوق اللوحة مع بقاء التبويبات ظاهرة.'
                    : 'Works inside pages opened above the dashboard while keeping navigation visible.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              value: _swipeBackEnabled,
              onChanged: (v) async {
                await AppGesturePreferences.setSwipeBackEnabled(v);
                if (!mounted) return;
                setState(() => _swipeBackEnabled = v);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.keyboard_tab_rounded),
              title: Text(
                _isAr
                    ? 'السحب من أطراف الشاشة فقط'
                    : 'Swipe from screen edges only',
              ),
              subtitle: Text(
                _isAr
                    ? 'مفيد لتقليل الرجوع غير المقصود أثناء تحريك الخرائط أو القوائم.'
                    : 'Helps reduce accidental back gestures while moving maps or lists.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              value: _edgeOnlySwipeBack,
              onChanged: _swipeBackEnabled
                  ? (v) async {
                      await AppGesturePreferences.setEdgeOnlySwipeBack(v);
                      if (!mounted) return;
                      setState(() => _edgeOnlySwipeBack = v);
                    }
                  : null,
            ),
          ],
          if (supportsKeyboard)
            SwitchListTile(
              secondary: const Icon(Icons.keyboard_return_rounded),
              title: Text(
                _isAr
                    ? 'زر Esc أو زر الرجوع في المتصفح'
                    : 'Esc or browser Back key',
              ),
              subtitle: Text(
                _isAr
                    ? 'اختصار مناسب للويب والكمبيوتر للرجوع داخل صفحات التطبيق.'
                    : 'A web and desktop shortcut for going back inside app pages.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              value: _keyboardBackEnabled,
              onChanged: (v) async {
                await AppGesturePreferences.setKeyboardBackEnabled(v);
                if (!mounted) return;
                setState(() => _keyboardBackEnabled = v);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _openComplianceUrl(String url, {String? errorLabel}) async {
    final u = Uri.tryParse(url.trim());
    if (u == null || !(u.hasScheme && u.hasAuthority)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorLabel ??
                (_isAr ? 'رابط غير صالح' : 'Invalid link'),
          ),
        ),
      );
      return;
    }
    try {
      if (await canLaunchUrl(u)) {
        await launchUrl(u, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr ? 'تعذر فتح الرابط' : 'Could not open link',
          ),
        ),
      );
    }
  }

  Widget _platformComplianceCard() {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final uid = _sb.auth.currentUser?.id ?? '';
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              _isAr
                  ? 'سياسات المنصة، الروابط الحكومية، والشكاوى'
                  : 'Policies, government links, and complaints',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _isAr
                  ? 'مراجع داخلية للامتثال مع متطلبات الوساطة والتسويق العقاري؛ تُحدَّث الروابط من إعدادات الخادم/ملف البيئة عند الاعتماد.'
                  : 'Internal references for brokerage/marketing compliance; URLs can be overridden via server env when approved.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ListTile(
            leading: Icon(Icons.article_outlined, color: cs.primary),
            title: Text(_isAr ? 'سياسات المنصة (تبويبات)' : 'Platform policies (tabs)'),
            subtitle: Text(
              _isAr
                  ? 'شروط الاستخدام، الخصوصية، الملكية الفكرية، الكوكيز'
                  : 'Terms, privacy, IP, cookies',
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: cs.primary),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => PlatformPoliciesScreen(isAr: _isAr),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.tune_outlined, color: cs.primary),
            title: Text(_isAr ? 'إدارة موافقات الكوكيز' : 'Cookie consent preferences'),
            subtitle: Text(
              _isAr
                  ? 'تحليلات / تسويق — يُزامَن مع الخادم عند توفر الترحيل'
                  : 'Analytics / marketing — synced when migration is applied',
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: cs.primary),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ConsentPreferencesScreen(isAr: _isAr),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.shield_outlined, color: cs.primary),
            title: Text(_isAr ? 'MFA (قريباً)' : 'MFA (coming soon)'),
            subtitle: Text(
              _isAr
                  ? 'المصادقة متعددة العوامل — جاهزية تشغيلية بعد ربط مزوّد الهوية'
                  : 'Multi-factor authentication — operational after IdP wiring',
            ),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _isAr
                        ? 'سيتم تفعيل MFA بعد اعتماد النفاذ الوطني / مزوّد OIDC.'
                        : 'MFA will be enabled after Nafath / OIDC approval.',
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.fact_check_outlined, color: cs.primary),
            title: Text(_isAr ? 'قائمة تحضير الترخيص (682010…)' : 'Licensing prep checklist'),
            subtitle: Text(
              _isAr ? 'للمشغّل — مراجعة مع مستشار' : 'For the operator — legal review',
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: cs.primary),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      RegulatoryOperatorChecklistScreen(isAr: _isAr),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.support_agent_outlined, color: cs.primary),
            title: Text(t.supportLabel),
            subtitle: Text(
              _isAr ? 'الدعم الفني واستقبال الشكاوى' : 'Support & complaints intake',
            ),
            trailing: Icon(Icons.open_in_new_rounded, color: cs.primary),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => SupportPage(
                    userId: uid,
                    isAr: _isAr,
                    bankColor: cs.primary,
                  ),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.account_balance_outlined, color: cs.primary),
            title: Text(_isAr ? 'الهيئة العامة للعقار (بوابة عامة)' : 'REGA (public portal)'),
            trailing: Icon(Icons.open_in_new_rounded, color: cs.primary),
            onTap: () =>
                unawaited(_openComplianceUrl(PlatformComplianceConfig.regaPublicUrl())),
          ),
          ListTile(
            leading: Icon(Icons.verified_user_outlined, color: cs.primary),
            title: Text(_isAr ? 'النفاذ الوطني الموحّد' : 'Nafath'),
            trailing: Icon(Icons.open_in_new_rounded, color: cs.primary),
            onTap: () => unawaited(
                _openComplianceUrl(PlatformComplianceConfig.nafathPublicUrl())),
          ),
          ListTile(
            leading: Icon(Icons.business_center_outlined, color: cs.primary),
            title: Text(
              _isAr ? 'المركز السعودي للأعمال' : 'Saudi Business Center',
            ),
            trailing: Icon(Icons.open_in_new_rounded, color: cs.primary),
            onTap: () => unawaited(
                _openComplianceUrl(PlatformComplianceConfig.mcBusinessCenterUrl())),
          ),
        ],
      ),
    );
  }

  // =========================
  // Layout: web tabs + mobile hub
  // =========================

  List<_SettingsSection> _visibleSettingsSections() {
    // تبويبات مدمجة بلا تكرار — «المؤسسة» تُدار من «إدارتي».
    final out = <_SettingsSection>[
      _SettingsSection.profile,
      _SettingsSection.security,
      _SettingsSection.devices, // يشمل الجلسات في المحتوى
      _SettingsSection.appDevice, // يشمل الصلاحيات
      _SettingsSection.notificationsPreferences, // تنبيهات + مظهر + إيماءات
      _SettingsSection.discovery,
      _SettingsSection.platformCompliance,
      _SettingsSection.danger, // حذف الحساب
    ];
    return out;
  }

  String _settingsSectionTitle(_SettingsSection s) {
    final t = AppLocalizations.of(context);
    switch (s) {
      case _SettingsSection.profile:
        return _isAr ? 'الملف الشخصي' : 'Profile';
      case _SettingsSection.accountHub:
        return t?.settingsSectionAccountHub ??
            (_isAr ? 'الحساب والجولة التعريفية' : 'Account & guided tour');
      case _SettingsSection.security:
        return _isAr ? 'الأمان والدخول السريع' : 'Security & quick login';
      case _SettingsSection.organization:
        return _isAr ? 'المؤسسة' : 'Organization';
      case _SettingsSection.devices:
        return _isAr ? 'الأجهزة والجلسات' : 'Devices & sessions';
      case _SettingsSection.sessions:
        return t?.settingsSectionSessionHistory ??
            (_isAr ? 'سجل الجلسات' : 'Session history');
      case _SettingsSection.discovery:
        return _isAr ? 'الاستكشاف' : 'Discovery';
      case _SettingsSection.appDevice:
        return _isAr ? 'التطبيق والصلاحيات' : 'App & permissions';
      case _SettingsSection.permissions:
        return _isAr ? 'حالة الصلاحيات' : 'Permission status';
      case _SettingsSection.notificationsPreferences:
        return _isAr ? 'التنبيهات والمظهر' : 'Alerts & appearance';
      case _SettingsSection.platformCompliance:
        return _isAr ? 'الامتثال والسياسات' : 'Compliance & policies';
      case _SettingsSection.gestures:
        return _isAr ? 'الإيماءات' : 'Gestures';
      case _SettingsSection.danger:
        return _isAr ? 'حذف الحساب' : 'Delete account';
    }
  }

  /// عنوان مختصر لشريط التبويب على الويب.
  String _settingsSectionTabLabel(_SettingsSection s) {
    switch (s) {
      case _SettingsSection.profile:
        return _isAr ? 'الملف' : 'Profile';
      case _SettingsSection.accountHub:
        return _isAr ? 'حساب' : 'Account';
      case _SettingsSection.security:
        return _isAr ? 'الأمان' : 'Security';
      case _SettingsSection.organization:
        return _isAr ? 'مؤسسة' : 'Org';
      case _SettingsSection.devices:
        return _isAr ? 'أجهزة' : 'Devices';
      case _SettingsSection.sessions:
        return _isAr ? 'جلسات' : 'Sessions';
      case _SettingsSection.discovery:
        return _isAr ? 'استكشاف' : 'Explore';
      case _SettingsSection.appDevice:
        return _isAr ? 'تطبيق' : 'App';
      case _SettingsSection.permissions:
        return _isAr ? 'صلاحيات' : 'Perms';
      case _SettingsSection.notificationsPreferences:
        return _isAr ? 'تنبيهات' : 'Alerts';
      case _SettingsSection.platformCompliance:
        return _isAr ? 'امتثال' : 'Legal';
      case _SettingsSection.gestures:
        return _isAr ? 'إيماءات' : 'Gestures';
      case _SettingsSection.danger:
        return _isAr ? 'حذف' : 'Delete';
    }
  }

  IconData _settingsSectionIcon(_SettingsSection s) {
    switch (s) {
      case _SettingsSection.profile:
        return Icons.person_outline_rounded;
      case _SettingsSection.accountHub:
        return Icons.hub_outlined;
      case _SettingsSection.security:
        return Icons.lock_outline_rounded;
      case _SettingsSection.organization:
        return Icons.apartment_rounded;
      case _SettingsSection.devices:
        return Icons.devices_rounded;
      case _SettingsSection.sessions:
        return Icons.history_rounded;
      case _SettingsSection.discovery:
        return Icons.explore_outlined;
      case _SettingsSection.appDevice:
        return Icons.phone_android_rounded;
      case _SettingsSection.permissions:
        return Icons.privacy_tip_outlined;
      case _SettingsSection.notificationsPreferences:
        return Icons.tune_rounded;
      case _SettingsSection.platformCompliance:
        return Icons.gavel_outlined;
      case _SettingsSection.gestures:
        return Icons.swipe_rounded;
      case _SettingsSection.danger:
        return Icons.delete_forever_rounded;
    }
  }

  Widget _organizationManagementCard() {
    final t = AppLocalizations.of(context)!;
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(t.orgTeamManagement),
            trailing: Text(
              _isAr ? 'فتح' : 'Open',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.orgTeamManagement,
            ),
          ),
          ListTile(
            title: Text(t.orgMonitoring),
            trailing: Text(
              _isAr ? 'فتح' : 'Open',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.orgMonitoring,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _settingsSectionContent(_SettingsSection s) {
    switch (s) {
      case _SettingsSection.profile:
        return [
          _profileCompletionCheckCard(),
          const SizedBox(height: 12),
          _profileCard(),
          const SizedBox(height: 12),
          _accountHubCard(),
        ];
      case _SettingsSection.accountHub:
        return [_accountHubCard()];
      case _SettingsSection.security:
        return [_securityCard()];
      case _SettingsSection.organization:
        // مخفي من الشريط — يُدار من «إدارتي».
        return const [];
      case _SettingsSection.devices:
        return [
          _devicesCard(),
          const SizedBox(height: 12),
          _sessionsCard(),
        ];
      case _SettingsSection.sessions:
        return [_sessionsCard()];
      case _SettingsSection.discovery:
        return [_exploreCityCard()];
      case _SettingsSection.appDevice:
        return [
          _deviceInfoCard(),
          const SizedBox(height: 12),
          _permissionsCard(),
        ];
      case _SettingsSection.permissions:
        return [_permissionsCard()];
      case _SettingsSection.notificationsPreferences:
        return [
          _notificationsCard(),
          const SizedBox(height: 12),
          _preferencesCard(),
          if (AppGesturePreferences.shouldShowSettings) ...[
            const SizedBox(height: 12),
            _gesturesCard(),
          ],
        ];
      case _SettingsSection.platformCompliance:
        return [_platformComplianceCard()];
      case _SettingsSection.gestures:
        return [_gesturesCard()];
      case _SettingsSection.danger:
        return [_dangerZone(context)];
    }
  }

  Widget _sectionPaneHeader(_SettingsSection s) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
      child: Row(
        children: [
          Icon(_settingsSectionIcon(s), color: cs.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _settingsSectionTitle(s),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionPaneBody(_SettingsSection s) {
    // ويب ويندوز والشاشات العريضة: عمود واحد داخل القسم (بدون شبكة بطاقات).
    final children = _settingsSectionContent(s);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _sectionPaneHeader(s),
        ...children,
      ],
    );
  }

  Widget _mobileChevron() {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Icon(
      rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }

  Widget _mobileHubList(List<_SettingsSection> sections) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final s in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              elevation: 0,
              color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _mobileDetail = s),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  child: Row(
                    textDirection: Directionality.of(context),
                    children: [
                      Icon(
                        _settingsSectionIcon(s),
                        color: cs.primary,
                        size: 26,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _settingsSectionTitle(s),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      _mobileChevron(),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _webSettingsTabs(List<_SettingsSection> sections) {
    var initialIndex = 0;
    if (widget.focusPresenceDisplay || widget.focusProfileCompletion) {
      final i = sections.indexOf(_SettingsSection.profile);
      if (i >= 0) initialIndex = i;
    }
    return DefaultTabController(
      length: sections.length,
      initialIndex: initialIndex.clamp(0, sections.isEmpty ? 0 : sections.length - 1),
      key: ValueKey(
        '${sections.map((e) => e.name).join('|')}#$_settingsContentEpoch'
        '${widget.focusPresenceDisplay ? '#presence' : ''}'
        '${widget.focusProfileCompletion ? '#complete' : ''}',
      ),
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tabs: [
                for (final s in sections)
                  Tab(
                    height: 44,
                    child: Text(
                      _settingsSectionTabLabel(s),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final s in sections)
                  _SettingsSectionLazyPane(
                    contentEpoch: _settingsContentEpoch,
                    builder: () => _sectionPaneBody(s),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // BUILD
  // =========================
  @override
  Widget build(BuildContext context) {
    final canNavPop = Navigator.of(context).canPop();
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<String>(
          valueListenable: langNotifier,
          builder: (context, __, ___) {
            final useHub = _useCompactSettingsHub;
            final inHubDetail = useHub && _mobileDetail != null;
            return Directionality(
              textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
              child: PopScope(
                // على الويب: اسمح بالرجوع داخل المسار بدل الخروج من التطبيق.
                canPop: inHubDetail ? false : (!kIsWeb || canNavPop),
                onPopInvokedWithResult: (didPop, _) {
                  if (didPop) return;
                  if (inHubDetail && mounted) {
                    setState(() => _mobileDetail = null);
                    return;
                  }
                  if (canNavPop) {
                    Navigator.of(context).maybePop();
                  }
                },
                child: Scaffold(
                  appBar: !widget.embedAppBar
                      ? AppBar(
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _isAr ? 'الإعدادات' : 'Settings',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: inHubDetail ? 12.5 : 17,
                                  height: 1.15,
                                  color: inHubDetail
                                      ? Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                      : null,
                                ),
                              ),
                              if (inHubDetail) ...[
                                const SizedBox(height: 1),
                                Text(
                                  _settingsSectionTitle(_mobileDetail!),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          leading: inHubDetail
                              ? IconButton(
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  tooltip:
                                      _isAr ? 'رجوع للقائمة' : 'Back to list',
                                  onPressed: () =>
                                      setState(() => _mobileDetail = null),
                                )
                              : (canNavPop
                                  ? BackButton(
                                      onPressed: () =>
                                          Navigator.of(context).maybePop(),
                                    )
                                  : null),
                          automaticallyImplyLeading: false,
                        )
                      : null,
                  body: Builder(
                    builder: (context) {
                      final sections = _visibleSettingsSections();
                      if (useHub) {
                        if (_mobileDetail == null) {
                          return _mobileHubList(sections);
                        }
                        return _sectionPaneBody(_mobileDetail!);
                      }
                      return _webSettingsTabs(sections);
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// يعيد بناء محتوى التبويب مع كل إطار أب — حتى تعمل المفاتيح والأزرار فوراً.
class _SettingsSectionLazyPane extends StatefulWidget {
  const _SettingsSectionLazyPane({
    required this.builder,
    required this.contentEpoch,
  });

  final Widget Function() builder;
  final int contentEpoch;

  @override
  State<_SettingsSectionLazyPane> createState() =>
      _SettingsSectionLazyPaneState();
}

class _SettingsSectionLazyPaneState extends State<_SettingsSectionLazyPane>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // لا تُخزَّن شجرة قديمة — وإلا تتجمّد المفاتيح بعد أول زيارة للتبويب.
    return KeyedSubtree(
      key: ValueKey<int>(widget.contentEpoch),
      child: widget.builder(),
    );
  }
}
