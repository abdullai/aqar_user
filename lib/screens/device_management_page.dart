import 'dart:async';
import 'dart:ui' as ui show TextDirection;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth/safe_sign_out_service.dart';
import '../core/haptics/app_haptics.dart';
import '../core/navigation/app_orphan_route_chrome.dart';
import '../core/notifications/app_sound_coordinator.dart';
import '../core/security/screen_protection.dart';
import '../core/utils/users_profiles_safe_select.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/fast_login_service.dart';
import '../services/notification_service.dart';
import '../services/user_install_session_service.dart';
import '../core/navigation/post_auth_navigation.dart';
import '../core/navigation/web_interaction_recovery.dart';
import '../services/user_session_coordination_service.dart';

String _deviceManagementUserMessage(
  Object e, {
  required bool isAr,
}) {
  if (e is TimeoutException) {
    return isAr
        ? 'انتهت المهلة. تحقق من الاتصال ثم أعد المحاولة.'
        : 'Timed out. Check your connection and retry.';
  }
  if (e is PostgrestException) {
    final msg = e.message.toLowerCase();
    final code = (e.code ?? '').trim();
    if (code == '42501' ||
        msg.contains('permission denied') ||
        msg.contains('jwt')) {
      return isAr ? 'لا صلاحية لهذه العملية.' : 'Not allowed for this action.';
    }
    if (msg.contains('network') ||
        msg.contains('failed host lookup') ||
        msg.contains('socket')) {
      return isAr ? 'تعذّر الاتصال بالخادم.' : 'Could not reach the server.';
    }
    return isAr
        ? 'تعذّر إكمال العملية. حاول لاحقاً.'
        : 'Could not complete the action. Try again later.';
  }
  return isAr ? 'حدث خطأ غير متوقع.' : 'Unexpected error.';
}

/// شاشة إدارة الأجهزة عند تجاوز حدّ جهازين — النصوص بالعربية عبر [AppLocalizations].
class DeviceManagementPage extends StatefulWidget {
  const DeviceManagementPage({
    super.key,
    this.mandatory = false,
    this.onMandatoryResolved,
  });

  final bool mandatory;
  final Future<void> Function()? onMandatoryResolved;

  @override
  State<DeviceManagementPage> createState() => _DeviceManagementPageState();
}

class _DeviceManagementPageState extends State<DeviceManagementPage> {
  bool _loading = true;
  bool _signingOut = false;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  String _currentFp = '';

  @override
  void initState() {
    super.initState();
    // أوقف استرداد الويب أثناء إدارة الأجهزة حتى لا يُغلق حوار OTP.
    if (kIsWeb) {
      WebInteractionRecovery.cancelScheduledRecovery();
    }
    if (widget.mandatory) {
      unawaited(ScreenProtection.enable());
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    if (widget.mandatory) {
      unawaited(ScreenProtection.disable());
    }
    super.dispose();
  }

  Future<void> _load() async {
    final isAr = Localizations.localeOf(context).languageCode != 'en';
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _currentFp = await UserInstallSessionService.installDeviceKey()
          .timeout(const Duration(seconds: 12));
      final data = await Supabase.instance.client
          .from('user_devices')
          .select()
          .order('last_seen', ascending: false)
          .timeout(const Duration(seconds: 22));
      final list = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _deviceManagementUserMessage(e, isAr: isAr);
        _loading = false;
      });
    }
  }

  Future<String?> _deviceFlowUsername() async {
    final saved =
        (await FastLoginService.getUsernameNationalId())?.trim() ?? '';
    if (saved.isNotEmpty) return FastLoginService.normalizeDigits(saved);

    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return null;

    String digits(dynamic value) {
      final s = FastLoginService.normalizeDigits((value ?? '').toString());
      return s.replaceAll(RegExp(r'\D'), '');
    }

    final row = await UsersProfilesSafeSelect.fetchProfileById(
      Supabase.instance.client,
      uid,
      columnAttempts: const [
        'user_id,username,unified_national_number',
        'user_id,username',
        'user_id',
      ],
    );
    if (row != null) {
      for (final key in const [
        'username',
        'unified_national_number',
        'license_no',
      ]) {
        final v = digits(row[key]);
        if (v.length == 10) {
          await FastLoginService.saveUserContext(
            uid: uid,
            usernameNationalId: v,
          );
          return v;
        }
      }
    }

    final metadata = Supabase.instance.client.auth.currentUser?.userMetadata;
    if (metadata != null) {
      for (final key in const ['username', 'national_id', 'license_no']) {
        final v = digits(metadata[key]);
        if (v.length == 10) return v;
      }
    }
    return null;
  }

  Future<String?> _canonicalDeviceFlowUsername() async {
    final raw = await _deviceFlowUsername();
    if (raw == null || raw.trim().isEmpty) return null;
    return AuthService.securityUsernameForDeviceFlow(raw);
  }

  String _formatDeviceTimestamp(dynamic raw, {required bool isAr}) {
    if (raw == null) return '—';
    DateTime? dt;
    if (raw is DateTime) {
      dt = raw.toLocal();
    } else {
      dt = DateTime.tryParse(raw.toString())?.toLocal();
    }
    if (dt == null) return '—';
    final locale = isAr ? 'ar' : 'en';
    return DateFormat.yMMMd(locale).add_jm().format(dt);
  }

  String _friendlyBrowserLabel(Map<String, dynamic> r, {required bool isAr}) {
    final raw = '${r['device_label'] ?? ''}'.trim();
    if (raw.isEmpty) {
      final platform = '${r['platform'] ?? ''}'.trim().toLowerCase();
      if (platform.isNotEmpty) {
        return isAr ? 'متصفح $platform' : 'Browser: $platform';
      }
      return isAr ? 'جهاز غير معروف' : 'Unknown device';
    }
    final lower = raw.toLowerCase();
    if (lower.startsWith('web:')) {
      final name = raw.substring(4).trim();
      final n = name.toLowerCase();
      if (n.contains('chrome')) return 'Google Chrome';
      if (n.contains('safari')) return 'Safari';
      if (n.contains('firefox')) return 'Firefox';
      if (n.contains('edge')) return 'Microsoft Edge';
      return isAr ? 'متصفح $name' : 'Browser: $name';
    }
    return raw;
  }

  String _platformLabel(Map<String, dynamic> r, {required bool isAr}) {
    final platform = '${r['platform'] ?? ''}'.trim();
    if (platform.isEmpty) return '—';
    final p = platform.toLowerCase();
    if (p == 'web') return isAr ? 'ويب' : 'Web';
    if (p == 'android') return isAr ? 'أندرويد' : 'Android';
    if (p == 'ios') return isAr ? 'iOS' : 'iOS';
    return platform;
  }

  Widget _deviceDetailRow({
    required String label,
    required String value,
    required ColorScheme cs,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard({
    required Map<String, dynamic> row,
    required bool isAr,
    required AppLocalizations? l10n,
    required ColorScheme cs,
  }) {
    final fp = '${row['device_fingerprint'] ?? ''}'.trim();
    final isSelf = fp == _currentFp;
    final browser = _friendlyBrowserLabel(row, isAr: isAr);
    final platform = _platformLabel(row, isAr: isAr);
    final lastSeen = _formatDeviceTimestamp(
      row['last_seen'] ?? row['updated_at'],
      isAr: isAr,
    );
    final registered = _formatDeviceTimestamp(row['created_at'], isAr: isAr);
    final rawCity = '${row['city'] ?? row['last_signin_city'] ?? ''}'.trim();
    final city = rawCity.isEmpty ? '—' : rawCity;

    final colBrowser =
        l10n?.securityDeviceColBrowser ?? (isAr ? 'المتصفح' : 'Browser');
    final colPlatform =
        l10n?.securityDeviceColPlatform ?? (isAr ? 'المنصة' : 'Platform');
    final colLocation =
        l10n?.securityDeviceColLocation ?? (isAr ? 'الموقع' : 'Location');
    final colLast =
        l10n?.securityDeviceColLastSignIn ?? (isAr ? 'آخر دخول' : 'Last sign-in');
    final colRegistered = l10n?.securityDeviceColRegistered ??
        (isAr ? 'تاريخ التسجيل' : 'Registered');
    final colStatus =
        l10n?.securityDeviceColStatus ?? (isAr ? 'الحالة' : 'Status');
    final statusCurrent = l10n?.securityDeviceStatusCurrent ??
        (isAr ? 'هذا الجهاز' : 'This device');
    final removeLabel =
        l10n?.securityDeviceRemoveAction ?? (isAr ? 'حذف' : 'Remove');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.devices_other_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    browser,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (isSelf)
                  Chip(
                    label: Text(statusCurrent),
                    visualDensity: VisualDensity.compact,
                  )
                else
                  IconButton(
                    tooltip: removeLabel,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _requestOtpAndRemove('${row['id']}'),
                  ),
              ],
            ),
            const Divider(height: 18),
            _deviceDetailRow(label: colPlatform, value: platform, cs: cs),
            _deviceDetailRow(label: colLocation, value: city, cs: cs),
            _deviceDetailRow(label: colLast, value: lastSeen, cs: cs),
            _deviceDetailRow(label: colRegistered, value: registered, cs: cs),
            _deviceDetailRow(
              label: colStatus,
              value: isSelf ? statusCurrent : '—',
              cs: cs,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesTable({
    required bool isAr,
    required AppLocalizations? l10n,
    required ColorScheme cs,
  }) {
    final colBrowser =
        l10n?.securityDeviceColBrowser ?? (isAr ? 'المتصفح' : 'Browser');
    final colPlatform =
        l10n?.securityDeviceColPlatform ?? (isAr ? 'المنصة' : 'Platform');
    final colLocation =
        l10n?.securityDeviceColLocation ?? (isAr ? 'الموقع' : 'Location');
    final colLast =
        l10n?.securityDeviceColLastSignIn ?? (isAr ? 'آخر دخول' : 'Last sign-in');
    final colRegistered = l10n?.securityDeviceColRegistered ??
        (isAr ? 'تاريخ التسجيل' : 'Registered');
    final colStatus =
        l10n?.securityDeviceColStatus ?? (isAr ? 'الحالة' : 'Status');
    final statusCurrent = l10n?.securityDeviceStatusCurrent ??
        (isAr ? 'هذا الجهاز' : 'This device');
    final removeLabel =
        l10n?.securityDeviceRemoveAction ?? (isAr ? 'حذف' : 'Remove');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(cs.surfaceContainerHighest),
          columns: [
            DataColumn(label: Text(colBrowser)),
            DataColumn(label: Text(colPlatform)),
            DataColumn(label: Text(colLocation)),
            DataColumn(label: Text(colLast)),
            DataColumn(label: Text(colRegistered)),
            DataColumn(label: Text(colStatus)),
            DataColumn(label: Text(removeLabel)),
          ],
          rows: _rows.map((r) {
            final fp = '${r['device_fingerprint'] ?? ''}'.trim();
            final isSelf = fp == _currentFp;
            return DataRow(
              cells: [
                DataCell(Text(
                  _friendlyBrowserLabel(r, isAr: isAr),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                )),
                DataCell(Text(_platformLabel(r, isAr: isAr))),
                DataCell(Text(
                  '${r['city'] ?? r['last_signin_city'] ?? ''}'.trim().isEmpty
                      ? '—'
                      : '${r['city'] ?? r['last_signin_city']}',
                )),
                DataCell(Text(_formatDeviceTimestamp(
                  r['last_seen'] ?? r['updated_at'],
                  isAr: isAr,
                ))),
                DataCell(Text(_formatDeviceTimestamp(
                  r['created_at'],
                  isAr: isAr,
                ))),
                DataCell(isSelf
                    ? Chip(
                        label: Text(statusCurrent),
                        visualDensity: VisualDensity.compact,
                      )
                    : const Text('—')),
                DataCell(isSelf
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: removeLabel,
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _requestOtpAndRemove('${r['id']}'),
                      )),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  double _listBottomPadding(BuildContext context) {
    if (widget.mandatory) return 16;
    return 16 +
        AppOrphanRouteChrome.bottomInset(context) +
        MediaQuery.paddingOf(context).bottom;
  }

  Future<void> _requestOtpAndRemove(String deviceId) async {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final isAr = lang != 'en';

    final username = await _canonicalDeviceFlowUsername();
    if (username == null || username.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr
                ? 'لم يُعثر على اسم المستخدم المحفوظ.'
                : 'Saved username not found.',
          ),
        ),
      );
      return;
    }

    final verified = await _showDeviceOtpDialog(
      title: l10n?.securityDeviceRemoveConfirm ??
          (isAr ? 'حذف الجهاز' : 'Remove device'),
      username: username,
    );

    if (!verified || !mounted) {
      return;
    }

    try {
      await Supabase.instance.client
          .from('user_devices')
          .delete()
          .eq('id', deviceId)
          .timeout(const Duration(seconds: 18));
      await _load();
      await _completeMandatoryDeviceRegistrationIfNeeded();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1600),
          content: Text(isAr ? 'تم حذف الجهاز' : 'Device removed'),
        ),
      );
      // بعد حذف جهاز (مسار إعدادات): العودة للوحة الرئيسية دون البقاء في شاشة العدّ.
      if (!widget.mandatory) {
        unawaited(PostAuthNavigation.openDashboard(context));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_deviceManagementUserMessage(e, isAr: isAr)),
        ),
      );
    }
  }

  Future<void> _completeMandatoryDeviceRegistrationIfNeeded() async {
    final reg = await UserInstallSessionService.retryRegisterDeviceSlot();
    if (!mounted) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (!reg.ok || !widget.mandatory || uid == null) return;

    final hints = await UserInstallSessionService.sessionHintsForBump();
    await UserSessionCoordinationService.afterSignIn(
      uid,
      cityHint: hints.city,
      deviceLabel: hints.label,
    );
    if (!mounted) return;

    final callback = widget.onMandatoryResolved;
    if (callback != null) {
      await callback();
      return;
    }

    if (!mounted) return;
    unawaited(PostAuthNavigation.openDashboard(context));
  }

  Future<bool> _showDeviceOtpDialog({
    required String title,
    required String username,
  }) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _DeviceOtpDialog(
            title: title,
            username: username,
          ),
        ) ??
        false;
    if (widget.mandatory && mounted) {
      unawaited(ScreenProtection.enable());
    }
    return result;
  }

  Future<bool> _confirmOtpForDeviceChange() async {
    final lang = Localizations.localeOf(context).languageCode;
    final isAr = lang != 'en';

    final username = await _canonicalDeviceFlowUsername();
    if (username == null || username.trim().isEmpty) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr
                ? 'لم يُعثر على اسم المستخدم المحفوظ.'
                : 'Saved username not found.',
          ),
        ),
      );
      return false;
    }

    return _showDeviceOtpDialog(
      title: isAr ? 'تأكيد تغيير الأجهزة' : 'Confirm device change',
      username: username,
    );
  }

  Future<void> _clearOthers() async {
    final isAr = Localizations.localeOf(context).languageCode != 'en';
    try {
      final otpOk = await _confirmOtpForDeviceChange();
      if (!otpOk || !mounted) return;

      final payload = await UserInstallSessionService.devicePayloadForRpc();
      await Supabase.instance.client
          .rpc(
            'clear_user_devices_except_current',
            params: {'p_device': payload},
          )
          .timeout(const Duration(seconds: 22));
      await UserInstallSessionService.registerDeviceSlotAfterSignIn();
      await _load();
      await _completeMandatoryDeviceRegistrationIfNeeded();
      if (!mounted) return;
      // بعد المسح الإلزامي: أغلق شاشة الأجهزة وادخل اللوحة — لا تُبقِ شاشة أجهزة ثانية.
      if (widget.mandatory) {
        return;
      }
      if (!widget.mandatory) {
        unawaited(PostAuthNavigation.openDashboard(context));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_deviceManagementUserMessage(e, isAr: isAr)),
        ),
      );
    }
  }

  Future<void> _confirmMandatorySignOut(BuildContext context) async {
    final lang = Localizations.localeOf(context).languageCode;
    final isAr = lang != 'en';
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(isAr ? 'تسجيل الخروج؟' : 'Sign out?'),
            content: Text(
              isAr
                  ? 'ستخرج من الحساب ويمكنك لاحقاً إدارة الأجهزة بعد الدخول من جديد.'
                  : 'You will leave this account. You can manage devices again after signing in.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(isAr ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(isAr ? 'تسجيل الخروج' : 'Sign out'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await SafeSignOutService.signOutAndNavigateToLogin(context);
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final isAr = lang != 'en';

    return PopScope(
      canPop: !widget.mandatory,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n?.securityDeviceManagementTitle ?? 'Devices'),
          automaticallyImplyLeading: !widget.mandatory,
          actions: widget.mandatory
              ? [
                  TextButton(
                    onPressed: (_loading || _signingOut)
                        ? null
                        : () => _confirmMandatorySignOut(context),
                    child: Text(isAr ? 'تسجيل الخروج' : 'Sign out'),
                  ),
                ]
              : null,
        ),
        body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    _listBottomPadding(context),
                  ),
                  children: [
                    Text(
                      l10n?.securityDeviceLimitMessage ?? '',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, c) {
                        final cs = Theme.of(context).colorScheme;
                        final wide = c.maxWidth >= 760;
                        if (wide) {
                          return _buildDevicesTable(
                            isAr: isAr,
                            l10n: l10n,
                            cs: cs,
                          );
                        }
                        return Column(
                          children: _rows
                              .map(
                                (r) => _buildDeviceCard(
                                  row: r,
                                  isAr: isAr,
                                  l10n: l10n,
                                  cs: cs,
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _rows.length <= 1 ? null : _clearOthers,
                      icon: const Icon(Icons.phonelink_erase_outlined),
                      label: Text(
                        l10n?.securityClearOtherDevices ?? 'Clear others',
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}

class _DeviceOtpDialog extends StatefulWidget {
  const _DeviceOtpDialog({
    required this.title,
    required this.username,
  });

  final String title;
  final String username;

  @override
  State<_DeviceOtpDialog> createState() => _DeviceOtpDialogState();
}

class _DeviceOtpDialogState extends State<_DeviceOtpDialog>
    with SingleTickerProviderStateMixin {
  static const int _otpLen = 4;
  static const int _maxSeconds = 60;
  static const int _maxAttempts = 3;

  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocus = FocusNode();

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  Timer? _timer;
  Timer? _bannerTimer;
  Timer? _otpPollTimer;
  OverlayEntry? _bannerEntry;

  DateTime? _expiresAt;
  DateTime? _otpRequestStartedAt;
  final ValueNotifier<int> _secondsLeftVn = ValueNotifier<int>(_maxSeconds);
  int _attemptsLeft = _maxAttempts;
  bool _error = false;
  bool _submitting = false;
  bool _sending = false;
  bool _bannerPinnedManual = false;
  String _otp = '';
  String? _lastBannerCode;
  int _lastBannerAtMs = 0;

  bool get _isAr {
    try {
      final t = AppLocalizations.of(context);
      if (t == null) {
        return Directionality.of(context) == ui.TextDirection.rtl;
      }
      return t.localeName.toLowerCase().startsWith('ar');
    } catch (_) {
      return Directionality.of(context) == ui.TextDirection.rtl;
    }
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
    unawaited(ScreenProtection.enable());
    unawaited(NotificationService.init());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_requestCode());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpPollTimer?.cancel();
    _removeBanner();
    _pulseController.dispose();
    _otpController.dispose();
    _otpFocus.dispose();
    _secondsLeftVn.dispose();
    unawaited(ScreenProtection.disable());
    super.dispose();
  }

  void _toast(String msg, {Duration duration = const Duration(milliseconds: 1800)}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: duration,
        dismissDirection: DismissDirection.horizontal,
        content: Text(msg),
      ),
    );
  }

  String _mapOtpSendError(String? hint) {
    final h = (hint ?? '').trim().toLowerCase();
    if (h == 'timeout') {
      return _isAr
          ? 'انتهت مهلة إرسال الرمز. تحقق من الاتصال.'
          : 'Sending the code timed out. Check your connection.';
    }
    if (h == 'invalid_username') {
      return _isAr
          ? 'بيانات المستخدم غير صالحة لهذه الخطوة.'
          : 'Invalid username for this step.';
    }
    if (h.contains('too many') || h.contains('rate')) {
      return _isAr
          ? 'طلبات كثيرة. انتظر قليلاً ثم أعد المحاولة.'
          : 'Too many attempts. Wait briefly and retry.';
    }
    if (h.contains('network') ||
        h.contains('failed host lookup') ||
        h.contains('socket')) {
      return _isAr
          ? 'تعذّر الاتصال بالخادم.'
          : 'Could not reach the server.';
    }
    return _isAr
        ? 'تعذّر إرسال رمز التحقق. تحقق من الشبكة أو حاول لاحقاً.'
        : 'Could not send the verification code. Check your network or retry.';
  }

  Future<void> _requestCode() async {
    if (_sending) return;
    _otpRequestStartedAt = DateTime.now().toUtc().subtract(
          const Duration(seconds: 2),
        );
    setState(() {
      _sending = true;
      _error = false;
      _otp = '';
      _otpController.clear();
      _expiresAt = DateTime.now().toUtc().add(
            const Duration(seconds: _maxSeconds),
          );
      _secondsLeftVn.value = _maxSeconds;
    });
    _startTimer();

    String? errHint;
    try {
      errHint = await AuthService.requestOtpWithMessage(widget.username)
          .timeout(const Duration(seconds: 22));
      if (errHint != null && mounted) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        errHint = await AuthService.requestOtpWithMessage(widget.username)
            .timeout(const Duration(seconds: 22));
      }
    } on TimeoutException {
      errHint = 'timeout';
    }
    if (!mounted) return;
    setState(() => _sending = false);

    if (errHint != null) {
      _toast(_mapOtpSendError(errHint));
      return;
    }

    await _fetchLatestOtpAndAnnounce();
    if (!mounted) return;
    _startOtpPolling();
    final t = AppLocalizations.of(context);
    _toast(t?.securityDeviceOtpSent ??
        (_isAr ? 'تم إرسال رمز التحقق' : 'Verification code sent'));
  }

  void _startOtpPolling() {
    _otpPollTimer?.cancel();
    var ticks = 0;
    _otpPollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      ticks++;
      if (!mounted || ticks > 18) {
        t.cancel();
        _otpPollTimer = null;
        return;
      }
      final row = await _latestOtpRow();
      final code = _codeFromRow(row);
      if (code != null && mounted) {
        final exp = _expiryFromRow(row);
        if (exp != null) {
          // لا setState هنا — يعيد بناء PinCode ويفقد التركيز/اللصق على الويب.
          _expiresAt = exp.isUtc ? exp : exp.toUtc();
          _startTimer();
        }
        _onIncomingOtp(code);
        t.cancel();
        _otpPollTimer = null;
      }
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final exp = _expiresAt;
    if (exp == null) return;
    final diff = exp.difference(DateTime.now().toUtc()).inSeconds;
    if (diff <= 0) {
      _timer?.cancel();
      // لا setState على الحوار كاملاً — كان يعيد بناء PinCode ويُفقد التركيز/اللصق على الويب.
      _secondsLeftVn.value = 0;
      return;
    }
    _secondsLeftVn.value = diff;
  }

  Future<void> _fetchLatestOtpAndAnnounce() async {
    const delays = <int>[200, 600, 1200, 2000, 3200, 4800, 6500, 8500];
    for (final ms in delays) {
      await Future<void>.delayed(Duration(milliseconds: ms));
      if (!mounted) return;
      final row = await _latestOtpRow();
      final code = _codeFromRow(row);
      if (code == null) continue;

      final exp = _expiryFromRow(row);
      if (exp != null) {
        setState(() => _expiresAt = exp.isUtc ? exp : exp.toUtc());
        _startTimer();
      }
      _onIncomingOtp(code);
      return;
    }
  }

  Future<Map<String, dynamic>?> _latestOtpRow() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      var q = Supabase.instance.client
          .from('in_app_notifications')
          .select('type, body, data, created_at, user_id')
          .eq('type', 'otp');
      if (uid != null && uid.isNotEmpty) {
        q = q.eq('user_id', uid);
      }
      final rows = await q
          .order('created_at', ascending: false)
          .limit(5)
          .timeout(const Duration(seconds: 12));
      final since = _otpRequestStartedAt;
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        if ((row['type'] ?? '').toString().toLowerCase() != 'otp') continue;
        // تجاهل رموز دخول قديمة — كانت تغلق الحوار فوراً بعد الملء.
        if (since != null) {
          final created = DateTime.tryParse('${row['created_at'] ?? ''}');
          if (created != null) {
            final createdUtc = created.isUtc ? created : created.toUtc();
            if (createdUtc.isBefore(since)) continue;
          }
        }
        return row;
      }
    } catch (_) {}
    return null;
  }

  String? _codeFromRow(Map<String, dynamic>? row) {
    if (row == null) return null;
    final data = row['data'];
    if (data is Map) {
      final code =
          (data['code'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (code.length >= _otpLen) return code.substring(0, _otpLen);
    } else if (data != null) {
      final only = data.toString().replaceAll(RegExp(r'\D'), '');
      if (only.length >= _otpLen) return only.substring(0, _otpLen);
    }
    final body = (row['body'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    if (body.length >= _otpLen) return body.substring(0, _otpLen);
    return null;
  }

  DateTime? _expiryFromRow(Map<String, dynamic>? row) {
    if (row == null) return null;
    final data = row['data'];
    if (data is Map) {
      return DateTime.tryParse((data['expiresAt'] ?? '').toString());
    }
    if (data != null) {
      final m =
          RegExp(r'expiresAt"\s*:\s*"([^"]+)"').firstMatch(data.toString());
      if (m != null) return DateTime.tryParse(m.group(1) ?? '');
    }
    return null;
  }

  void _onIncomingOtp(String text) {
    final only = text.replaceAll(RegExp(r'\D'), '');
    if (only.isEmpty) return;
    final code = only.length >= _otpLen ? only.substring(0, _otpLen) : only;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastBannerCode == code && (now - _lastBannerAtMs) < 1200) return;

    _lastBannerCode = code;
    _lastBannerAtMs = now;
    // بانر علوي واحد + صوت — بدون SnackBar مكرر للرمز.
    unawaited(_playAndNotifyOtp());
    _showBanner(code);
  }

  Future<void> _playAndNotifyOtp() async {
    final title = _isAr ? 'رمز التحقق' : 'Verification code';
    final publicBody = _isAr
        ? 'وصل رمز تحقق إلى هاتفك. افتح التطبيق وأدخل الرمز في الشاشة.'
        : 'A verification code was sent. Open the app and enter it on screen.';

    if (kIsWeb) {
      await AppSoundCoordinator.playUiEffect(
        assetPath: 'sounds/otp_chime.wav',
        volume: 1.0,
      );
    } else {
      await NotificationService.showOtpNotification(
        title: title,
        body: publicBody,
        playChannelSound: true,
      );
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          await HapticFeedback.mediumImpact();
        } catch (_) {}
      }
    }
    if (mounted) {
      unawaited(_pulseController.forward().then((_) {
        if (mounted) _pulseController.reverse();
      }));
    }
  }

  void _showBanner(String code) {
    if (!mounted) return;
    _removeBanner();
    _bannerPinnedManual = false;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final border = isDark
        ? Colors.white.withOpacity(0.10)
        : Colors.black.withOpacity(0.08);
    final titleColor = isDark ? Colors.white : const Color(0xFF0B1220);
    final bodyColor =
        isDark ? const Color(0xFFD1D5DB) : const Color(0xFF475569);

    _bannerEntry = OverlayEntry(
      builder: (_) => IgnorePointer(
        ignoring: false,
        child: SafeArea(
          top: true,
          bottom: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 0),
            child: Align(
              alignment: Alignment.topCenter,
              child: Material(
                elevation: 12,
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: border),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                          color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.notifications_active_outlined,
                              color: titleColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _isAr
                                        ? 'تم استلام رمز التحقق'
                                        : 'Verification code received',
                                    style: TextStyle(
                                      color: titleColor,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    _isAr
                                        ? 'رمز التحقق: $code'
                                        : 'Your code: $code',
                                    style: TextStyle(
                                      color: bodyColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                AppHaptics.selection();
                                Clipboard.setData(ClipboardData(text: code));
                                _removeBanner();
                                _applyIncomingCode(code, fromUserAction: true);
                                _toast(
                                  _isAr ? 'تم لصق الرمز' : 'Code pasted',
                                  duration: const Duration(milliseconds: 1400),
                                );
                              },
                              child: Text(_isAr ? 'لصق' : 'Paste'),
                            ),
                            TextButton(
                              onPressed: () {
                                AppHaptics.selection();
                                _bannerPinnedManual = true;
                                _bannerTimer?.cancel();
                                _bannerTimer = null;
                                _otpFocus.requestFocus();
                              },
                              child: Text(_isAr ? 'إدخال يدوي' : 'Manual'),
                            ),
                            TextButton(
                              onPressed: _removeBanner,
                              child: Text(_isAr ? 'إلغاء' : 'Cancel'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final overlay = Overlay.of(context, rootOverlay: true);
    overlay.insert(_bannerEntry!);
    _bannerTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted || _bannerPinnedManual) return;
      _removeBanner();
    });
  }

  void _removeBanner() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    _bannerPinnedManual = false;
    _bannerEntry?.remove();
    _bannerEntry = null;
  }

  String _otpDigitsFromUi() {
    final fromCtrl = _otpController.text.replaceAll(RegExp(r'\D'), '');
    final fromState = _otp.replaceAll(RegExp(r'\D'), '');
    if (fromCtrl.length >= _otpLen) return fromCtrl.substring(0, _otpLen);
    if (fromState.length >= _otpLen) return fromState.substring(0, _otpLen);
    return fromCtrl.length > fromState.length ? fromCtrl : fromState;
  }

  void _applyIncomingCode(String text, {required bool fromUserAction}) {
    final only = text.replaceAll(RegExp(r'\D'), '');
    if (only.isEmpty) return;
    final take = (only.length >= _otpLen ? only.substring(0, _otpLen) : only)
        .padLeft(_otpLen, '0');
    setState(() {
      _otp = take;
      _otpController.text = take;
      _otpController.selection = TextSelection.collapsed(offset: take.length);
      _error = false;
    });
    _otpFocus.requestFocus();
    _maybeAutoSubmit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeAutoSubmit();
    });
  }

  void _maybeAutoSubmit() {
    if (_submitting) return;
    final raw = _otpDigitsFromUi();
    if (raw.length == _otpLen) {
      unawaited(_submit());
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final entered = _otpDigitsFromUi();
    if (_secondsLeftVn.value <= 0) {
      AppHaptics.medium();
      setState(() => _error = true);
      _toast(_isAr
          ? 'انتهت صلاحية الرمز. أعد الإرسال.'
          : 'Code expired. Resend it.');
      return;
    }
    if (entered.length != _otpLen) {
      AppHaptics.medium();
      setState(() => _error = true);
      _toast(_isAr ? 'الرجاء إدخال الرمز كاملاً' : 'Enter the full code');
      return;
    }

    setState(() => _submitting = true);
    try {
      final verified = await AuthService.verifyInAppOtp(
        usernameDigits: widget.username,
        code: entered,
      );
      if (!mounted) return;
      if (!verified) {
        AppHaptics.vibrate();
        setState(() {
          _attemptsLeft--;
          _error = true;
        });
        if (_attemptsLeft <= 0) {
          _toast(_isAr
              ? 'تم تجاوز عدد المحاولات. أعد إرسال الرمز.'
              : 'Too many attempts. Resend the code.');
          setState(() {
            _secondsLeftVn.value = 0;
            _attemptsLeft = _maxAttempts;
          });
          _timer?.cancel();
          return;
        }
        _toast(_isAr
            ? 'الرمز غير صحيح. المتبقي: $_attemptsLeft'
            : 'Invalid code. Left: $_attemptsLeft');
        return;
      }

      await NotificationService.clearOtpNotifications();
      _timer?.cancel();
      _removeBanner();
      if (!mounted) return;
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resendCode() async {
    if (_secondsLeftVn.value > 0) {
      final t = AppLocalizations.of(context);
      _toast(t?.securityDeviceOtpResendWait ??
          (_isAr
              ? 'انتظر انتهاء العداد قبل إعادة الإرسال'
              : 'Wait for the timer before resending'));
      return;
    }
    setState(() {
      _attemptsLeft = _maxAttempts;
      _error = false;
    });
    await _requestCode();
  }

  Widget _otpField() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveBorder = isDark
        ? Colors.white.withOpacity(0.18)
        : Colors.black.withOpacity(0.10);
    final primary = cs.primary;
    final fill = isDark
        ? Colors.white.withOpacity(0.06)
        : Colors.black.withOpacity(0.04);
    final border = _error ? cs.error : primary;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_pulseAnimation.value * 0.025),
          child: child,
        );
      },
      child: PinCodeTextField(
        appContext: context,
        length: _otpLen,
        controller: _otpController,
        focusNode: _otpFocus,
        autoDisposeControllers: false,
        autoFocus: true,
        keyboardType: TextInputType.number,
        enableActiveFill: true,
        animationType: AnimationType.fade,
        animationDuration: const Duration(milliseconds: 120),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(_otpLen),
        ],
        mainAxisAlignment: MainAxisAlignment.center,
        pinTheme: PinTheme(
          shape: PinCodeFieldShape.box,
          borderRadius: BorderRadius.circular(12),
          fieldHeight: 56,
          fieldWidth: 50,
          inactiveColor: _error ? cs.error : inactiveBorder,
          activeColor: border.withOpacity(0.65),
          selectedColor: border,
          inactiveFillColor: fill,
          selectedFillColor: fill,
          activeFillColor: fill,
          borderWidth: 1.4,
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 22,
        ),
        onChanged: (v) {
          final only = v.replaceAll(RegExp(r'\D'), '');
          _otp = only.length > _otpLen ? only.substring(0, _otpLen) : only;
          // لا setState على كل رقم — كان يعيد بناء الحقل ويمنع اللصق على الويب.
          if (_error) {
            setState(() => _error = false);
          }
          _maybeAutoSubmit();
        },
        onCompleted: (_) {
          AppHaptics.selection();
          _maybeAutoSubmit();
        },
        beforeTextPaste: (text) {
          final only = (text ?? '').replaceAll(RegExp(r'\D'), '');
          if (only.isEmpty) return true;
          AppHaptics.selection();
          _applyIncomingCode(only, fromUserAction: true);
          _toast(_isAr ? 'تم لصق الرمز' : 'Code pasted', duration: const Duration(milliseconds: 1200));
          return false;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final subColor = Theme.of(context).textTheme.bodySmall?.color;

    return Directionality(
      textDirection: _isAr ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: AlertDialog(
        title: Text(widget.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t?.securityDeviceOtpHint ??
                    (_isAr
                        ? 'أدخل رمز التحقق المرسل لهاتفك المسجّل.'
                        : 'Enter the verification code sent to your phone.'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Directionality(
                textDirection: ui.TextDirection.ltr,
                child: _otpField(),
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<int>(
                valueListenable: _secondsLeftVn,
                builder: (context, secondsLeft, _) {
                  final showResend = secondsLeft <= 0;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timer_outlined, size: 18, color: subColor),
                      const SizedBox(width: 6),
                      Text(
                        showResend
                            ? (_isAr ? 'انتهى الوقت' : 'Time expired')
                            : (_isAr
                                ? 'المتبقي: $secondsLeft ث'
                                : 'Remaining: $secondsLeft s'),
                        style: TextStyle(
                          color: subColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed:
                            showResend && !_sending ? _resendCode : null,
                        icon: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(_isAr ? 'إعادة إرسال' : 'Resend'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.pop(context, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(t?.securityOk ?? (_isAr ? 'تأكيد' : 'Confirm')),
          ),
        ],
      ),
    );
  }
}
