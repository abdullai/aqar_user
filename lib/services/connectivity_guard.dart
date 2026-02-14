// lib/services/connectivity_guard.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// خدمة مركزية لفحص الاتصال بالإنترنت
/// تستخدم قبل أي دخول / OTP / Supabase call
class ConnectivityGuard {
  static final Connectivity _connectivity = Connectivity();

  /// فحص فوري: هل يوجد إنترنت أم لا
  static Future<bool> hasInternet() async {
    final result =
        await _connectivity.checkConnectivity(); // List<ConnectivityResult>
    return !result.contains(ConnectivityResult.none);
  }

  /// Stream لمتابعة تغيّر حالة الاتصال (اختياري لاحقاً)
  static Stream<bool> onStatusChange() {
    return _connectivity.onConnectivityChanged
        .map((list) => !list.contains(ConnectivityResult.none))
        .distinct();
  }
}
