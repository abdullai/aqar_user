import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../../screens/post_auth_shell.dart';
import '../../screens/user_dashboard.dart';
import 'post_auth_navigation.dart';
import 'web_dashboard_mount_guard.dart';
import 'web_bootstrap_diag.dart';
import 'web_dashboard_pointer_host.dart';
import 'web_interaction_recovery.dart';

/// ويب: مسار `/userDashboard` — ضيف ومسجّل عبر [UserDashboard] (بطاقات موحّدة).
///
/// مهم: غلاف واحد فقط عبر [hostKey]. إعادة فتح اللوحة بعد الدخول تُحدّث
/// نفس الـ State بدل إنشاء لوحة ثانية (كان يسبب duplicate bootstrap وتجمّد).
class WebDashboardShell extends StatefulWidget {
  const WebDashboardShell({super.key, required this.lang});

  final String lang;

  /// مفتاح ثابت لاستعادة الغلاف الحي من [StartRouter].
  static final GlobalKey hostKey =
      GlobalKey(debugLabel: 'aqar-web-dashboard-shell');

  /// إن وُجد غلاف حي: أعد حل وضع الدخول (ضيف↔مستخدم) دون remount كامل.
  static Future<bool> reloadActiveEntryMode() async {
    final state = hostKey.currentState;
    if (state is! _WebDashboardShellState || !state.mounted) return false;
    await state.reloadEntryMode();
    return true;
  }

  @override
  State<WebDashboardShell> createState() => _WebDashboardShellState();
}

class _WebDashboardShellState extends State<WebDashboardShell> {
  late final bool _isPrimaryMount;
  bool _mountDashboard = false;
  bool _usePostAuth = false;
  bool _isGuestPrefs = false;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _isPrimaryMount = WebDashboardMountGuard.claim();
    if (!kIsWeb || !_isPrimaryMount) {
      if (kIsWeb && !_isPrimaryMount) {
        WebBootstrapDiag.warn(
          'dashboard.shell',
          'duplicate mount blocked (Page Unresponsive guard)',
        );
      }
      return;
    }

    WebDashboardBootstrapGuard.reset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isPrimaryMount) return;
      WebInteractionRecovery.dismissStuckOverlaysOnce();
      WebInteractionRecovery.scheduleDashboardRecovery(
        forDuration: const Duration(seconds: 12),
      );
    });
    unawaited(_resolveEntryMode());

    // ضيف → دخول: حدّث نفس الغلاف بدل فتح Shell ثانٍ.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted || !_isPrimaryMount) return;
      if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.signedOut ||
          data.event == AuthChangeEvent.initialSession) {
        unawaited(_resolveEntryMode());
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _authSub = null;
    if (_isPrimaryMount) {
      WebDashboardBootstrapGuard.reset();
      WebInteractionRecovery.cancelScheduledRecovery();
    }
    WebDashboardMountGuard.release();
    super.dispose();
  }

  Future<void> reloadEntryMode() => _resolveEntryMode();

  Future<void> _resolveEntryMode() async {
    if (!_isPrimaryMount) return;
    await PostAuthNavigation.prepareForDashboardEntry();

    final prefs = await SharedPreferences.getInstance();
    final guestMode = prefs.getBool(AppConfig.prefGuestModeKey) ?? false;
    final entryMode =
        (prefs.getString(AppConfig.prefEntryModeKey) ?? '').trim().toLowerCase();
    final session = Supabase.instance.client.auth.currentSession;
    final sessionUser = session?.user;

    // جلسة مسجّلة تتقدّم على تفضيل الضيف القديم.
    final isGuest = sessionUser == null && (guestMode || entryMode == 'guest');
    final usePostAuth =
        sessionUser != null && sessionUser.id.trim().isNotEmpty;

    if (!mounted) return;
    final changed = !_mountDashboard ||
        _isGuestPrefs != isGuest ||
        _usePostAuth != usePostAuth;
    WebBootstrapDiag.log(
      'dashboard.shell',
      'mount guest=$isGuest postAuth=$usePostAuth '
          'ui=UserDashboard '
          'uid=${sessionUser?.id ?? "none"}'
          '${changed ? "" : " (unchanged)"}',
    );
    if (!changed) return;
    // ضيف → مستخدم: اسمح لـ UserDashboard الجديد بالـ bootstrap.
    if (!isGuest && _isGuestPrefs) {
      WebDashboardBootstrapGuard.reset();
    }
    setState(() {
      _isGuestPrefs = isGuest;
      _usePostAuth = usePostAuth;
      _mountDashboard = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && !_isPrimaryMount) {
      return const SizedBox.shrink();
    }

    if (!_mountDashboard) {
      return const ColoredBox(
        color: Color(0xFFF5F7FA),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // ضيف ومسجّل: نفس UserDashboard وبطاقات UnifiedRealEstateCard (كالاحتياطية).
    // لوحة WebGuestDashboard المبسّطة كانت تخفي الطلبات العقارية وتغيّر شكل البطاقات.
    final dashboard = UserDashboard(
      key: ValueKey(_isGuestPrefs ? 'dashboard-guest' : 'dashboard'),
      lang: widget.lang,
    );

    if (!_usePostAuth) {
      return WebDashboardPointerHost(child: dashboard);
    }

    return WebDashboardPointerHost(
      child: PostAuthShell(
        lang: widget.lang,
        child: dashboard,
      ),
    );
  }
}
