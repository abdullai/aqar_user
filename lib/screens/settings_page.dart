// lib/screens/settings_page.dart
import 'dart:async' show unawaited;
import 'dart:convert' show jsonDecode;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

import '../core/utils/search_normalize.dart';
import '../core/config/app_config.dart';
import '../core/input/saudi_input_formatters.dart';
import '../core/gestures/app_gesture_preferences.dart';
import '../core/utils/listing_date_display.dart';
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
import '../routes.dart';
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
import '../services/user_listing_preferences_service.dart';

/// أقسام الإعدادات — ويب: تبويب لكل قسم، جوال: صف يفتح الشاشة الفرعية.
enum _SettingsSection {
  profile,
  security,
  organization,
  devices,
  sessions,
  discovery,
  appDevice,
  permissions,
  notificationsPreferences,
  gestures,
  danger,
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

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

  final _sb = Supabase.instance.client;

  /// جوال: `null` = قائمة الأقسام، وإلا محتوى القسم المختار.
  _SettingsSection? _mobileDetail;

  @override
  void initState() {
    super.initState();

    _loadUser();
    _loadOrgOwnerFlag();
    _loadFastLogin();
    _loadDevices();
    _loadSessions();
    _loadGraceMinutes();
    unawaited(_loadDeviceAndAppInfo());
    unawaited(_loadPermissionSummary());
    unawaited(_loadChatNotificationPref());
    unawaited(_loadChatMessageSoundPref());
    unawaited(_loadHapticsPref());
    unawaited(_loadInAppSoundPref());
    unawaited(_loadGesturePrefs());
    unawaited(_loadPreferredExploreCity());
    unawaited(_loadLocalReportStats());
    _listingDateZone = ListingDateDisplay.zone;
    unawaited(_loadSyncLangPref());
    unawaited(_loadSyncThemePref());
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
                        child: TextField(
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
      final rows = <String>[];
      Future<void> add(Permission p, String label) async {
        final s = await p.status;
        final t = s.isGranted
            ? (_isAr ? 'مسموح' : 'Granted')
            : s.isDenied
                ? (_isAr ? 'مرفوض' : 'Denied')
                : s.isPermanentlyDenied
                    ? (_isAr ? 'مرفوض دائماً' : 'Permanently denied')
                    : s.toString();
        rows.add('$label: $t');
      }

      await add(Permission.camera, _isAr ? 'الكاميرا' : 'Camera');
      await add(Permission.photos, _isAr ? 'الصور' : 'Photos');
      await add(Permission.microphone, _isAr ? 'الميكروفون' : 'Microphone');
      await add(Permission.location, _isAr ? 'الموقع' : 'Location');
      await add(Permission.notification, _isAr ? 'الإشعارات' : 'Notifications');

      if (!mounted) return;
      setState(() => _permissionLines = rows);
    } catch (_) {}
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
        _orgOwner = ctx != null && ctx['is_owner'] == true;
      });
    } catch (_) {
      if (mounted) setState(() => _orgOwner = false);
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
        return _isAr ? 'مسوّق عقاري' : 'Marketer';
      case 'office':
        return _isAr ? 'مكتب عقاري' : 'Real-estate office';
      case 'company':
        return _isAr ? 'شركة عقارية' : 'Real-estate company';
      case 'institution':
        return _isAr ? 'مؤسسة عقارية' : 'Institution';
      case 'individual_seller':
        return _isAr ? 'فرد / مالك' : 'Individual / Owner';
      default:
        if (k.isEmpty) return _isAr ? 'غير محدد' : 'Not set';
        return raw;
    }
  }

  String _roleLabel() {
    switch (_roleKey) {
      case 'admin':
        return _isAr ? 'مشرف' : 'Administrator';
      case 'agent':
        return _isAr ? 'وسيط عقاري' : 'Agent';
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
      if (_isAr) {
        return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
      }
      return DateFormat.yMMMd('en').format(d);
    }
    return s;
  }

  Future<void> _loadUser() async {
    final u = _sb.auth.currentUser;
    if (u == null) return;

    try {
      final profile = await _sb
          .from('users_profiles')
          .select(
            'first_name_ar,second_name_ar,third_name_ar,fourth_name_ar,'
            'first_name_en,second_name_en,third_name_en,fourth_name_en,'
            'full_name_ar,full_name_en,full_name,'
            'avatar_url,phone,role,status,created_at,account_type,unified_national_number,'
            'public_member_id,chat_last_seen_hidden',
          )
          .eq('user_id', u.id)
          .maybeSingle();

      if (!mounted) return;

      if (profile == null) {
        final meta = u.userMetadata;
        final metaName =
            (meta?['full_name'] ?? meta?['name'] ?? '').toString().trim();
        setState(() {
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
      setState(() {
        _email = u.email ?? '';
        _fullDisplayName = _buildQuadrupleName(map, ar: _isAr);
        _phone = _pickStr(map, 'phone');
        _avatarUrl = _pickStr(map, 'avatar_url');

        final atRaw = _pickStr(map, 'account_type');
        _accountTypeRaw = atRaw;
        _accountCategory = atRaw.isEmpty
            ? (_isAr ? 'غير محدد' : 'Not set')
            : _accountCategoryLabel(atRaw);

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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _email = u.email ?? '';
        _accountCategory = _isAr ? 'تعذر تحميل الملف' : 'Profile load failed';
        _createdAt = '—';
      });
      debugPrint('settings _loadUser: $e');
    }
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
        content: TextField(
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
        _avatarUrl = publicUrl;
        _uploadingPhoto = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.profilePhotoUpdated)),
      );
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
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
              TextField(
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
  Future<void> _loadDevices() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;

      final data = await _sb
          .from('user_sessions')
          .select('id, device, last_active, created_at')
          .eq('user_id', uid)
          .order('last_active', ascending: false);

      if (!mounted) return;
      setState(() => _devices = List<Map<String, dynamic>>.from(data));
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
      await _sb.from('user_sessions').delete().eq('id', id);
      _loadDevices();
    } catch (_) {}
  }

  // =========================
  // LOGOUT ALL DEVICES
  // =========================
  Future<void> _logoutAllDevices() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;

      await _sb.from('user_sessions').delete().eq('user_id', uid);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isAr
              ? 'تم تسجيل الخروج من كل الأجهزة'
              : 'Logged out from all devices'),
        ),
      );

      _loadDevices();
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
          Text(
            displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          Text(
            _email,
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const Divider(),
          ListTile(
            title: Text(_accountCategory),
            subtitle: Text(t.accountCategoryLabel),
          ),
          ListTile(
            title: Text(_roleLabel()),
            subtitle: Text(t.permissionRoleLabel),
          ),
          ListTile(
            title: Text(_phone.isEmpty ? '—' : _phone),
            subtitle: Text(_isAr ? 'رقم الجوال' : 'Phone'),
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
          ],
          ListTile(
            title: Text(_accountStatus),
            subtitle: Text(_isAr ? 'حالة الحساب' : 'Account Status'),
          ),
          ListTile(
            title: Text(_createdAt.isEmpty ? '—' : _createdAt),
            subtitle: Text(_isAr ? 'تاريخ الإنشاء' : 'Created At'),
          ),
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
            subtitle: Text(t.settingsSupportMovedHint),
            trailing: Icon(Icons.info_outline,
                color: Theme.of(context).colorScheme.primary),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.settingsSupportMovedHint)),
              );
            },
          ),
        ],
      ),
    );
  }

  // =========================
  // SECURITY (mobile only)
  // =========================
  Widget _securityCard() {
    final t = AppLocalizations.of(context)!;
    if (!_isMobile) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _isAr
                ? 'قفل التطبيق بالبصمة أو الرمز السري يتاح على أندرويد وآيفون فقط.'
                : 'App lock with biometrics or PIN is available on Android and iOS only.',
          ),
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
                  ? 'القيمة الافتراضية 3 دقائق. تُستخدم مع تفعيل الدخول السريع أو البصمة.'
                  : 'Default is 3 minutes. Used when PIN or biometrics lock is enabled.',
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
              onPressed: () {
                AppSettings.openAppSettings();
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
    if (_devices.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _isAr ? 'لا توجد أجهزة مسجلة' : 'No registered devices',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._devices.map(
            (d) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _settingsKvRow(
                  label:
                      _isAr ? 'نوع الجهاز / الجلسة' : 'Device / session type',
                  value: _userSessionKindLine(d, t),
                ),
                Divider(
                    height: 1,
                    color: cs.outlineVariant.withValues(alpha: 0.35)),
                _settingsKvRow(
                  label: _isAr ? 'اسم الجهاز' : 'Device name',
                  value: _userSessionCardTitle(d),
                ),
                Divider(
                    height: 1,
                    color: cs.outlineVariant.withValues(alpha: 0.35)),
                _settingsKvRow(
                  label: _isAr ? 'آخر نشاط' : 'Last active',
                  value: _formatSessionTs(d['last_active'] ?? d['created_at']),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => _logoutDevice('${d['id']}'),
                    child: Text(_isAr ? 'إنهاء الجلسة' : 'Sign out'),
                  ),
                ),
                Divider(
                    height: 1,
                    color: cs.outlineVariant.withValues(alpha: 0.45)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              t.settingsDevicesFooterHint,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: FilledButton(
              onPressed: _logoutAllDevices,
              child: Text(_isAr
                  ? 'تسجيل الخروج من كل الأجهزة'
                  : 'Logout from all devices'),
            ),
          )
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
    if (_sessions.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _isAr ? 'لا يوجد سجل جلسات' : 'No session history',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Card(
      child: Column(
        children: _sessions
            .map(
              (s) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _settingsKvRow(
                    label: _isAr ? 'المنصة' : 'Platform',
                    value: _sessionKindLabel('${s['platform']}', t),
                  ),
                  Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.35)),
                  _settingsKvRow(
                    label: _isAr ? 'الحدث' : 'Event',
                    value: '${s['event'] ?? 'login'}',
                  ),
                  Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.35)),
                  _settingsKvRow(
                    label: _isAr ? 'اسم الجهاز / الوكيل' : 'Device / agent',
                    value: _deviceRowTitle(s),
                  ),
                  Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.35)),
                  _settingsKvRow(
                    label: _isAr ? 'الوقت' : 'Time',
                    value: _formatSessionTs(s['created_at']),
                  ),
                  Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.45)),
                ],
              ),
            )
            .toList(),
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
                    ? 'عند وصول رسالة أثناء استخدام التطبيق. الإشعارات عند قفل الشاشة تخضع أيضاً لإعدادات النظام.'
                    : 'When a message arrives while the app is open. Lock-screen alerts also follow system settings.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              value: _chatNotificationsEnabled,
              onChanged: (v) async {
                await ChatNotificationPrefs.setEnabled(v);
                if (!mounted) return;
                setState(() => _chatNotificationsEnabled = v);
              },
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                _isAr
                    ? 'تنبيهات الدردشة على الويب تختلف؛ راجع إعدادات المتصفح لإشعارات الموقع.'
                    : 'On web, chat push behavior depends on the browser; check site notification settings.',
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
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: List.generate(
                                AppConfig.primaryAccentCount, (i) {
                              final seed = AppConfig.accentSeedAt(i);
                              final selected = seed == accent;
                              return InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => setAppAccentIndex(i),
                                child: Ink(
                                  width: 40,
                                  height: 40,
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
      ],
    );
  }

  // =========================
  // DANGER ZONE
  // =========================
  Widget _dangerZone(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.error.withValues(alpha: 0.08),
      child: Column(
        children: [
          ListTile(
            title: Text(
              _isAr ? 'حذف الحساب' : 'Delete Account',
              style: TextStyle(
                color: cs.error,
                fontWeight: FontWeight.w800,
              ),
            ),
            onTap: _deleteAccount,
          )
        ],
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

  // =========================
  // Layout: web tabs + mobile hub
  // =========================

  List<_SettingsSection> _visibleSettingsSections() {
    final out = <_SettingsSection>[_SettingsSection.profile];
    out.add(_SettingsSection.security);
    if (_orgOwner) out.add(_SettingsSection.organization);
    out.addAll([
      _SettingsSection.devices,
      _SettingsSection.sessions,
      _SettingsSection.discovery,
      _SettingsSection.appDevice,
      _SettingsSection.permissions,
      _SettingsSection.notificationsPreferences,
      if (AppGesturePreferences.shouldShowSettings) _SettingsSection.gestures,
      _SettingsSection.danger,
    ]);
    return out;
  }

  String _settingsSectionTitle(_SettingsSection s) {
    final t = AppLocalizations.of(context);
    switch (s) {
      case _SettingsSection.profile:
        return _isAr ? 'الملف الشخصي' : 'Profile';
      case _SettingsSection.security:
        return _isAr ? 'الأمان والدخول السريع' : 'Security & quick login';
      case _SettingsSection.organization:
        return _isAr ? 'المؤسسة' : 'Organization';
      case _SettingsSection.devices:
        return t?.settingsSectionRegisteredDevices ??
            (_isAr ? 'الأجهزة المسجّلة' : 'Registered devices');
      case _SettingsSection.sessions:
        return t?.settingsSectionSessionHistory ??
            (_isAr ? 'سجل الجلسات' : 'Session history');
      case _SettingsSection.discovery:
        return _isAr ? 'الاستكشاف' : 'Discovery';
      case _SettingsSection.appDevice:
        return _isAr ? 'التطبيق والجهاز' : 'App & device';
      case _SettingsSection.permissions:
        return _isAr ? 'حالة الصلاحيات' : 'Permission status';
      case _SettingsSection.notificationsPreferences:
        return _isAr ? 'التنبيهات والمظهر' : 'Alerts & appearance';
      case _SettingsSection.gestures:
        return _isAr ? 'الإيماءات' : 'Gestures';
      case _SettingsSection.danger:
        return _isAr ? 'منطقة الخطر' : 'Danger zone';
    }
  }

  /// عنوان مختصر لشريط التبويب على الويب.
  String _settingsSectionTabLabel(_SettingsSection s) {
    switch (s) {
      case _SettingsSection.profile:
        return _isAr ? 'الملف' : 'Profile';
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
        return _isAr ? 'التطبيق' : 'App';
      case _SettingsSection.permissions:
        return _isAr ? 'صلاحيات' : 'Perms';
      case _SettingsSection.notificationsPreferences:
        return _isAr ? 'تنبيهات' : 'Alerts';
      case _SettingsSection.gestures:
        return _isAr ? 'إيماءات' : 'Gestures';
      case _SettingsSection.danger:
        return _isAr ? 'خطر' : 'Danger';
    }
  }

  IconData _settingsSectionIcon(_SettingsSection s) {
    switch (s) {
      case _SettingsSection.profile:
        return Icons.person_outline_rounded;
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
        return Icons.info_outline_rounded;
      case _SettingsSection.permissions:
        return Icons.privacy_tip_outlined;
      case _SettingsSection.notificationsPreferences:
        return Icons.tune_rounded;
      case _SettingsSection.gestures:
        return Icons.swipe_rounded;
      case _SettingsSection.danger:
        return Icons.warning_amber_rounded;
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
        return [_profileCard()];
      case _SettingsSection.security:
        return [_securityCard()];
      case _SettingsSection.organization:
        return [_organizationManagementCard()];
      case _SettingsSection.devices:
        return [_devicesCard()];
      case _SettingsSection.sessions:
        return [_sessionsCard()];
      case _SettingsSection.discovery:
        return [_exploreCityCard()];
      case _SettingsSection.appDevice:
        return [_deviceInfoCard()];
      case _SettingsSection.permissions:
        return [_permissionsCard()];
      case _SettingsSection.notificationsPreferences:
        return [
          _notificationsCard(),
          const SizedBox(height: 12),
          _preferencesCard(),
        ];
      case _SettingsSection.gestures:
        return [_gesturesCard()];
      case _SettingsSection.danger:
        return [_dangerZone(context)];
    }
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
    return DefaultTabController(
      length: sections.length,
      key: ValueKey(sections.map((e) => e.name).join('|')),
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
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: _settingsSectionContent(s),
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
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<String>(
          valueListenable: langNotifier,
          builder: (context, __, ___) {
            return Directionality(
              textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
              child: PopScope(
                canPop: !_isMobile || _mobileDetail == null,
                onPopInvokedWithResult: (didPop, _) {
                  if (didPop) return;
                  if (_isMobile && _mobileDetail != null && mounted) {
                    setState(() => _mobileDetail = null);
                  }
                },
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(
                      _isMobile && _mobileDetail != null
                          ? _settingsSectionTitle(_mobileDetail!)
                          : (_isAr ? 'الإعدادات' : 'Settings'),
                    ),
                    leading: _isMobile && _mobileDetail != null
                        ? IconButton(
                            icon: const Icon(Icons.arrow_back_rounded),
                            tooltip: _isAr ? 'رجوع للقائمة' : 'Back to list',
                            onPressed: () =>
                                setState(() => _mobileDetail = null),
                          )
                        : null,
                    automaticallyImplyLeading:
                        !_isMobile || _mobileDetail == null,
                  ),
                  body: Builder(
                    builder: (context) {
                      final sections = _visibleSettingsSections();
                      if (_isMobile) {
                        if (_mobileDetail == null) {
                          return _mobileHubList(sections);
                        }
                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: _settingsSectionContent(_mobileDetail!),
                        );
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
