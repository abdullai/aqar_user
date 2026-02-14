// lib/services/notification_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  NotificationService._();

  // =========================
  // Local notifications (OTP)
  // =========================
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _inited = false;

  static const AndroidNotificationChannel _otpChannel = AndroidNotificationChannel(
    'otp_channel',
    'OTP Notifications',
    description: 'Verification code notifications',
    importance: Importance.max,
    playSound: true,
  );

  // =========================
  // FCM (✅ web-safe)
  // =========================
  static StreamSubscription<String>? _tokenRefreshSub;

  // ✅ لا تُنشئ FirebaseMessaging.instance كـ static field
  static FirebaseMessaging get _fcm {
    // هذا getter يجب ألا يُستدعى على الويب
    return FirebaseMessaging.instance;
  }

  /// init local notifications + request permissions + sync FCM token to Supabase
  /// استدعه بعد توفر Session (بعد تسجيل الدخول)
  static Future<void> init() async {
    // ✅ على الويب: لا نستخدم FCM ولا local notifications
    // (الويب عندك ينهار بسبب firebase_messaging)
    if (kIsWeb) return;

    if (_inited) {
      await syncFcmTokenToSupabase();
      return;
    }
    _inited = true;

    // ----- Local init -----
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(initSettings);

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_otpChannel);
    }

    // ----- Permissions -----
    await requestPermissions();

    // ----- FCM sync -----
    await syncFcmTokenToSupabase();

    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _fcm.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) return;
      await _upsertToken(newToken);
    });
  }

  static Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _inited = false;
  }

  static Future<void> requestPermissions() async {
    if (kIsWeb) return;

    // Local permission
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    }

    // FCM permission (iOS + Android 13+)
    try {
      await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (e) {
      debugPrint('FCM requestPermission error: $e');
    }
  }

  // =========================
  // FCM -> Supabase
  // =========================
  static Future<void> syncFcmTokenToSupabase() async {
    if (kIsWeb) return;

    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;

    if (user == null) {
      debugPrint('No session yet; skip FCM token sync');
      return;
    }

    try {
      final token = await _fcm.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('FCM token is null/empty');
        return;
      }
      await _upsertToken(token);
    } catch (e) {
      debugPrint('FCM getToken error: $e');
    }
  }

  static Future<void> _upsertToken(String token) async {
    if (kIsWeb) return;

    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;
    if (user == null) return;

    final platform =
        Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other');

    final deviceId = await _deviceId();

    try {
      await sb.from('user_push_tokens').upsert(
        {
          'user_id': user.id,
          'fcm_token': token,
          'platform': platform,
          'device_id': deviceId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,device_id',
      );

      debugPrint('Saved FCM token user=${user.id} device=$deviceId');
    } catch (e) {
      debugPrint('Supabase upsert token error: $e');
    }
  }

  static Future<String> _deviceId() async {
    if (kIsWeb) return 'web';

    // بدون باكجات إضافية: prefix من التوكن كمعرّف جهاز
    try {
      final t = await _fcm.getToken();
      if (t != null && t.isNotEmpty) {
        return t.length >= 32 ? t.substring(0, 32) : t;
      }
    } catch (_) {}
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  // =========================
  // Local OTP notification
  // =========================
  static Future<void> showOtpNotification({
    required String title,
    required String body,
  }) async {
    // OTP local إشعارات — للموبايل فقط
    if (kIsWeb) return;
    if (!_inited) await init();

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _otpChannel.id,
        _otpChannel.name,
        channelDescription: _otpChannel.description,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }
}
