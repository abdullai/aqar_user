import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/no_internet_dialog.dart';

class AppSession extends ChangeNotifier {
  // =========================
  // Unified Keys (match main.dart)
  // =========================
  static const String kPrefGuestMode = 'guest_mode'; // bool
  static const String kPrefEntryMode = 'entry_mode'; // 'guest' | 'user'
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

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  bool _noInternetDialogOpen = false;

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
    if (kIsWeb) {
      // لا شيء على الويب
      return;
    }
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
    // ✅ على الويب: لا نستخدم connectivity_plus
    if (kIsWeb) {
      hasInternet = true;
      notifyListeners();
      return;
    }

    final first = await _connectivity.checkConnectivity();
    _applyConnectivity(first);

    _connSub?.cancel();
    _connSub = _connectivity.onConnectivityChanged.listen(_applyConnectivity);
  }

  void _applyConnectivity(List<ConnectivityResult> results) {
    final offline = results.contains(ConnectivityResult.none);
    final nextHasInternet = !offline;

    if (hasInternet == nextHasInternet) return;

    hasInternet = nextHasInternet;

    if (!hasInternet) {
      _netGuardToken++;
    }

    notifyListeners();
  }

  // =========================
  // Unified Guard Runner
  // =========================
  Future<T?> runNetworkGuarded<T>({
    required BuildContext context,
    required Future<T> Function() action,
    bool showDialogOnNoInternet = true,
    bool isAr = true,
  }) async {
    if (kIsWeb) {
      return await action();
    }

    if (!hasInternet) {
      if (showDialogOnNoInternet) {
        await _showNoInternetOnce(context, isAr: isAr);
      }
      return null;
    }

    final int startToken = _netGuardToken;

    try {
      final result = await action();

      if (startToken != _netGuardToken || !hasInternet) {
        return null;
      }

      return result;
    } catch (e) {
      if (!hasInternet && showDialogOnNoInternet) {
        await _showNoInternetOnce(context, isAr: isAr);
        return null;
      }
      rethrow;
    }
  }

  Future<void> _showNoInternetOnce(
    BuildContext context, {
    required bool isAr,
  }) async {
    if (_noInternetDialogOpen) return;
    _noInternetDialogOpen = true;
    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => NoInternetDialog(isAr: isAr),
      );
    } finally {
      _noInternetDialogOpen = false;
    }
  }

  // =========================
  // Cleanup
  // =========================
  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }
}
