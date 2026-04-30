// lib/core/session/app_session.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/connectivity_guard.dart';
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

    isGuest = guestMode || entryMode == 'guest';

    final uid = Supabase.instance.client.auth.currentUser?.id;
    userId = (uid != null && uid.isNotEmpty) ? uid : null;

    if (isGuest) {
      userId = null;
    }

    notifyListeners();
  }

  /// إعادة قراءة وضع الضيف/المستخدم من التخزين بعد تغيير المفاتيح يدويًا (مثل قبل تسجيل الدخول).
  Future<void> reloadFromPrefs() => _load();

  Future<void> setGuest() async {
    final prefs = await SharedPreferences.getInstance();

    // ✅ على الويب: لا تعمل signOut(local) تلقائيًا لتجنب loop/log spam
    await _signOutLocalSafely();

    isGuest = true;
    userId = null;

    await prefs.setBool(kPrefGuestMode, true);
    await prefs.setString(kPrefEntryMode, 'guest');

    notifyListeners();
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
    final uid = userId;
    if (isGuest || uid == null || uid.isEmpty) return;
    unawaited(_warmHomeFeedsAfterAuth());
  }

  Future<void> _warmHomeFeedsAfterAuth() async {
    try {
      final sb = Supabase.instance.client;
      await Future.wait([
        sb.from('properties').select('id').limit(1),
        sb.from('market_property_requests').select('id').limit(1),
      ]);
    } catch (_) {}
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();

    // ✅ على الويب: لا تعمل signOut(local) تلقائيًا
    await _signOutLocalSafely();

    await prefs.remove(kPrefGuestMode);
    await prefs.remove(kPrefEntryMode);

    await _clearOtpVerifiedKeys(prefs);

    userId = null;
    isGuest = false;

    notifyListeners();
  }

  Future<void> _signOutLocalSafely() async {
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
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
  Future<void> _startConnectivityListener() async {
    try {
      await _refreshReachabilityInternal();
    } catch (_) {
      hasInternet = false;
      _netGuardToken++;
      notifyListeners();
      _scheduleOfflinePolling();
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
    if (results.isNotEmpty && results.contains(ConnectivityResult.none)) {
      if (hasInternet) {
        hasInternet = false;
        _netGuardToken++;
        notifyListeners();
      }
      _scheduleOfflinePolling();
      return;
    }
    await _refreshReachabilityInternal();
  }

  void _scheduleOfflinePolling() {
    if (_offlinePollTimer != null) return;
    _offlinePollTimer = Timer.periodic(const Duration(seconds: 14), (_) {
      unawaited(_refreshReachabilityInternal());
    });
  }

  Future<void> _refreshReachabilityInternal() async {
    final ok = await ConnectivityGuard.hasReachableInternet();
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
