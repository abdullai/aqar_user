// lib/core/session/app_session.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/connectivity_guard.dart';
import '../../services/properties_home_feed_service.dart';
import '../../services/session_manager.dart';
import '../auth/auth_local_sign_out.dart';
import '../config/app_config.dart';

class AppSession extends ChangeNotifier {
  // =========================
  // Unified Keys ([AppConfig])
  // =========================
  static const String kPrefGuestMode = AppConfig.prefGuestModeKey;
  static const String kPrefEntryMode = AppConfig.prefEntryModeKey;
  static String otpVerifiedKey(String uid) => 'otp_verified_$uid';

  // =========================
  // Session State
  // =========================
  String? userId;
  bool isGuest = false;

  bool get isLoggedIn => (userId != null && userId!.isNotEmpty) && !isGuest;

  // =========================
  // Internet State
  // =========================
  bool hasInternet = true;

  /// أثناء ضغط المستخدم «إعادة المحاولة» على طبقة عدم الاتصال.
  bool networkCheckBusy = false;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _offlinePollTimer;

  // token لإبطال نتائج العمليات لو انقطع النت أثناء التنفيذ
  int _netGuardToken = 0;

  AppSession() {
    _load();
    _startConnectivityListener(); // intentionally not awaited
  }

  // =========================
  // Load / Persist
  // =========================
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    final bool guestMode = prefs.getBool(kPrefGuestMode) ?? false;
    final String entryMode =
        (prefs.getString(kPrefEntryMode) ?? '').toLowerCase();

    final uid = Supabase.instance.client.auth.currentUser?.id;
    // جلسة Auth حية تلغي وضع الضيف القديم في prefs (بعد دخول من وضع الضيف).
    if (uid != null && uid.isNotEmpty) {
      isGuest = false;
      userId = uid;
      if (guestMode || entryMode == 'guest') {
        unawaited(prefs.setBool(kPrefGuestMode, false));
        unawaited(prefs.setString(kPrefEntryMode, 'user'));
      }
    } else {
      isGuest = guestMode || entryMode == 'guest';
      userId = null;
    }

    notifyListeners();
  }

  /// إعادة قراءة وضع الضيف/المستخدم من التخزين بعد تغيير المفاتيح يدويًا (مثل قبل تسجيل الدخول).
  Future<void> reloadFromPrefs() => _load();

  /// عند بدء تسجيل الدخول من وضع الضيف: ألغِ علامة الضيف فوراً دون مسح جلسة Supabase.
  Future<void> prepareForUserLogin() async {
    final prefs = await SharedPreferences.getInstance();
    isGuest = false;
    await prefs.setBool(kPrefGuestMode, false);
    await prefs.setString(kPrefEntryMode, 'user');
    await prefs.remove(AppConfig.prefGuestLegacyIsGuestKey);
    await prefs.remove(AppConfig.prefGuestLegacyGuestKey);
    notifyListeners();
  }

  Future<void> setGuest() async {
    final prefs = await SharedPreferences.getInstance();

    // 1) اكتب وضع الضيف أولاً حتى يقرأ معالج signedOut الحالة الصحيحة ولا يستدعي logout().
    isGuest = true;
    userId = null;
    await prefs.setBool(kPrefGuestMode, true);
    await prefs.setString(kPrefEntryMode, 'guest');
    notifyListeners();

    // جوال + ويب: مسح JWT تحت duringPublicSessionReset حتى لا يعيد StartRouter التحميل
    // ولا تبقى جلسة قديمة تُفشّل طلبات الضيف (401 → تعليق بعد الدخول).
    try {
      await SessionManager.clearLocalAuthSessionForPublicReads(
        Supabase.instance.client,
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      unawaited(_detachSupabaseSessionForGuest());
    }
  }

  Future<void> _detachSupabaseSessionForGuest() async {
    try {
      if (Supabase.instance.client.auth.currentSession == null) return;
    } catch (_) {
      return;
    }
    try {
      await _signOutLocalSafely().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> setUser(String id) async {
    final prefs = await SharedPreferences.getInstance();

    userId = id;
    isGuest = false;

    await prefs.setBool(kPrefGuestMode, false);
    await prefs.setString(kPrefEntryMode, 'user');

    notifyListeners();
  }

  /// بعد تسجيل الدخول/التحقق: استعلامات خفيفة لتسريع أول ظهور للرئيسية (بدون UI).
  void schedulePostAuthHomeWarmup() {
    if (kIsWeb) return;
    final uid = userId;
    if (isGuest || uid == null || uid.isEmpty) return;
    unawaited(_warmHomeFeedsAfterAuth());
  }

  Future<void> _warmHomeFeedsAfterAuth() async {
    try {
      final sb = Supabase.instance.client;
      await Future.wait([
        PropertiesHomeFeedService.fetch(
          client: sb,
          filterSuppressed: false,
          limit: 1,
          allowBypassCircuit: true,
        ),
        sb.from('market_property_requests').select('id').limit(1),
      ]);
    } catch (_) {}
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      await _signOutLocalSafely().timeout(const Duration(seconds: 5));
    } catch (_) {}

    await prefs.remove(kPrefGuestMode);
    await prefs.remove(kPrefEntryMode);

    await _clearOtpVerifiedKeys(prefs);

    userId = null;
    isGuest = false;

    notifyListeners();
  }

  /// بعد [Supabase.auth.signOut] من الشاشة — لا يُعاد استدعاء signOut (قد يعلّق على الويب).
  Future<void> applyLocalLogoutAfterSupabaseSignOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kPrefGuestMode);
    await prefs.remove(kPrefEntryMode);
    await _clearOtpVerifiedKeys(prefs);
    userId = null;
    isGuest = false;
    notifyListeners();
  }

  /// مسح كاش الجلسة والصلاحيات (يُستدعى من مسارات الخروج الموحّدة).
  Future<void> clearAllCaches({String? supabaseUserId}) async {
    await SessionManager.clearPreferencesAfterLogout(supabaseUserId);
    userId = null;
    isGuest = false;
    notifyListeners();
  }

  Future<void> _signOutLocalSafely() async {
    try {
      await AuthLocalSignOut.signOutLocal(Supabase.instance.client);
    } catch (_) {}
  }

  Future<void> _clearOtpVerifiedKeys(SharedPreferences prefs) async {
    try {
      final keys = prefs.getKeys();
      final toRemove =
          keys.where((k) => k.startsWith('otp_verified_')).toList();
      for (final k in toRemove) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  // =========================
  // Connectivity
  // =========================
  /// رابط الشبكة فقط (بدون HTTP إلى Supabase).
  /// فشل/انتهاء مهلة الفحص لا يضع hasInternet=false — كان يجمّد التطبيق بعد الدخول.
  Future<void> _startConnectivityListener() async {
    try {
      await _refreshReachabilityInternal().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          // فشل مفتوح: نبقى متصلاً حتى يثبت المكوّن انقطاع الرابط فعلاً.
        },
      );
    } catch (_) {
      // فشل مفتوح — لا نفترض انقطاع الإنترنت.
    }

    _connSub?.cancel();
    try {
      _connSub = _connectivity.onConnectivityChanged.listen((results) {
        unawaited(_onConnectivityPluginChanged(results));
      });
    } catch (_) {
      _scheduleOfflinePolling();
    }
  }

  Future<void> _onConnectivityPluginChanged(
    List<ConnectivityResult> results,
  ) async {
    if (kIsWeb) {
      // على الويب: connectivity_plus قد يُبلّغ none خطأً — لا نحجب اللوحة.
      if (results.isNotEmpty && results.contains(ConnectivityResult.none)) {
        return;
      }
      await _refreshReachabilityInternal();
      return;
    }
    if (results.isNotEmpty && results.contains(ConnectivityResult.none)) {
      if (hasInternet) {
        hasInternet = false;
        _netGuardToken++;
        notifyListeners();
      }
      _scheduleOfflinePolling();
      return;
    }
    // عاد الرابط — حدّث فوراً من المكوّن دون انتظار HTTP.
    await _refreshReachabilityInternal();
  }

  void _scheduleOfflinePolling() {
    if (kIsWeb) return;
    if (_offlinePollTimer != null) return;
    _offlinePollTimer = Timer.periodic(const Duration(seconds: 14), (_) {
      unawaited(_refreshReachabilityInternal());
    });
  }

  Future<void> _refreshReachabilityInternal() async {
    // رابط الشبكة فقط — لا probeBackendReachable (كان يفشل تحت ضغط ما بعد الدخول).
    final ok = await ConnectivityGuard.hasPluginLink();
    if (kIsWeb) {
      if (ok && !hasInternet) {
        hasInternet = true;
        _offlinePollTimer?.cancel();
        _offlinePollTimer = null;
        notifyListeners();
      }
      return;
    }
    final prev = hasInternet;
    hasInternet = ok;
    if (!ok) {
      if (prev) {
        _netGuardToken++;
      }
      _scheduleOfflinePolling();
    } else {
      _offlinePollTimer?.cancel();
      _offlinePollTimer = null;
    }
    if (prev != ok) {
      notifyListeners();
    }
  }

  /// إعادة فحص الشبكة. [userInitiated] يعرض حالة تحميل على زر «إعادة المحاولة».
  Future<void> refreshConnectivity({bool userInitiated = false}) async {
    if (userInitiated) {
      networkCheckBusy = true;
      notifyListeners();
    }
    try {
      await _refreshReachabilityInternal();
    } finally {
      if (userInitiated) {
        networkCheckBusy = false;
        notifyListeners();
      }
    }
  }

  // =========================
  // Unified Guard Runner
  // =========================
  Future<T?> runNetworkGuarded<T>({
    required BuildContext context,
    required Future<T> Function() action,
    bool showDialogOnNoInternet = false,
    bool isAr = true,
  }) async {
    if (!hasInternet) {
      if (showDialogOnNoInternet && context.mounted) {
        final loc = Localizations.localeOf(context).languageCode != 'en';
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(loc ? 'لا يوجد اتصال بالإنترنت' : 'No internet connection'),
            content: Text(
              loc
                  ? 'تحقق من اتصالك ثم أعد المحاولة.'
                  : 'Check your connection and try again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(loc ? 'حسناً' : 'OK'),
              ),
            ],
          ),
        );
      }
      return null;
    }

    final int startToken = _netGuardToken;

    try {
      final result = await action();

      // ✅ FIX: لا تستخدم context بعد await إلا إذا مازال mounted
      if (!context.mounted) return null;

      if (startToken != _netGuardToken || !hasInternet) {
        return null;
      }

      return result;
    } catch (e) {
      // ✅ FIX
      if (!context.mounted) return null;

      if (!hasInternet) {
        return null;
      }
      rethrow;
    }
  }

  // =========================
  // Cleanup
  // =========================
  @override
  void dispose() {
    _offlinePollTimer?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}
