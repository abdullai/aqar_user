// lib/services/notification_service.dart
//
// مسارات منفصلة عن [AppSoundCoordinator]:
// - FCM + [showWorkflowLocalNotification]: أصوات/قنوات النظام.
// - [showOtpNotification] (غير الويب): قناة OTP؛ استخدم playChannelSound=false مع نغمة أصول
//   على نفس الحدث فقط على الويب/سطح المكتب حيث لا تُعرض القناة (انظر شاشة التحقق).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_navigation_service.dart';
import 'chat_notification_prefs.dart';

class NotificationService {
  NotificationService._();

  /// أيقونة شريط الإشعارات في أندرويد (drawable أبيض/شفاف).
  static const String androidNotificationIcon = 'ic_stat_aqar';

  // =========================
  // Local notifications (OTP)
  // =========================
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _inited = false;

  static const AndroidNotificationChannel _otpChannel =
      AndroidNotificationChannel(
    'otp_channel',
    'OTP Notifications',
    description: 'Verification code notifications',
    importance: Importance.max,
    playSound: true,
  );

  static const int _otpNotificationId = 91001;

  static const AndroidNotificationChannel _workflowChannel =
      AndroidNotificationChannel(
    'workflow_channel',
    'موثوق العقاري — التنبيهات',
    description: 'عروض، عقود، تصاريح، دردشة، وغيرها',
    importance: Importance.high,
    playSound: true,
  );

  // =========================
  // FCM (✅ web-safe)
  // =========================
  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<RemoteMessage>? _fcmForegroundSub;
  static StreamSubscription<RemoteMessage>? _fcmOpenedSub;

  static bool _fcmListenersBound = false;

  // ✅ لا تُنشئ FirebaseMessaging.instance كـ static field
  static FirebaseMessaging get _fcm {
    // هذا getter يجب ألا يُستدعى على الويب
    return FirebaseMessaging.instance;
  }

  /// تهيئة الويب: FCM فقط (بدون إشعارات محلية). يُلفّى بـ try/catch حتى لا يعطل الإقلاع.
  static Future<void> _initWeb() async {
    if (_inited) {
      await syncFcmTokenToSupabase();
      return;
    }
    try {
      final fcm = FirebaseMessaging.instance;
      // إذن إشعارات الويب يطلبه المتصفح عند الحاجة (لا شاشة إلزامية عند الإقلاع).
      try {
        final token = await fcm.getToken();
        if (token != null && token.isNotEmpty) {
          await _upsertToken(token, allowWeb: true);
        }
      } catch (_) {}
      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = fcm.onTokenRefresh.listen((newToken) async {
        if (newToken.isEmpty) return;
        await _upsertToken(newToken, allowWeb: true);
      });
      _inited = true;
    } catch (e, st) {
      debugPrint('NotificationService._initWeb: $e');
      debugPrint('$st');
    }
  }

  /// init local notifications + request permissions + sync FCM token to Supabase
  /// استدعه بعد توفر Session (بعد تسجيل الدخول)
  static Future<void> init() async {
    if (kIsWeb) {
      await _initWeb();
      return;
    }

    if (_inited) {
      await syncFcmTokenToSupabase();
      return;
    }
    _inited = true;

    // ----- Local init -----
    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_aqar');

    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        final p = details.payload;
        if (p != null && p.isNotEmpty) {
          PushNavigationService.handleLocalNotificationPayload(p);
        }
      },
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_otpChannel);
      await android?.createNotificationChannel(_workflowChannel);
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

  /// ربط التوجيه عند فتح إشعار + مستمعي المقدمة/النقر (يُستدعى مرة من واجهة التطبيق).
  static void bindFcmNavigation(GlobalKey<NavigatorState> navKey,
      {String Function()? langResolver}) {
    if (kIsWeb) return;
    PushNavigationService.attach(navKey, langResolver: langResolver);
    if (_fcmListenersBound) return;
    _fcmListenersBound = true;

    unawaited(_configureIosForegroundPresentation());

    _fcmForegroundSub = FirebaseMessaging.onMessage.listen((m) async {
      if (!_inited) await init();
      // في المقدمة (التطبيق مفتوح): لا نُظهر إشعاراً في درج النظام ولا نكرّر الصوت
      // مع شريط التطبيق الداخلي / Realtime؛ على iOS يُعطّل العرض الأمامي أدناه أيضاً.
      final life = WidgetsBinding.instance.lifecycleState;
      if (life == AppLifecycleState.resumed) {
        return;
      }

      final n = m.notification;
      final data = Map<String, dynamic>.from(m.data);
      final title = (n?.title ?? data['title_ar'] ?? data['title'] ?? 'موثوق العقاري')
          .toString();
      final body = (n?.body ?? data['body_ar'] ?? data['body'] ?? '').toString();
      if (body.isEmpty && n == null) return;

      final dedupe =
          '${m.messageId ?? ''}_${DateTime.now().millisecondsSinceEpoch ~/ 2000}';

      await showWorkflowLocalNotification(
        title: title,
        body: body.isEmpty ? title : body,
        dedupeKey: dedupe,
        payloadMap: data.map((k, v) => MapEntry(k, v.toString())),
      );
    });

    _fcmOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((m) {
      PushNavigationService.handleNotificationMap(m.data);
    });

    unawaited(_drainInitialFcmMessage());
  }

  static Future<void> _configureIosForegroundPresentation() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      // في المقدمة: لا تنبّه ولا صوت من FCM (يُتجنّب التكرار مع إشعارات أخرى).
      // الشارة تبقى للتحديث؛ الإشعارات عند الخلفية تبقى عبر النظام كالمعتاد.
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
    } catch (e) {
      debugPrint('setForegroundNotificationPresentationOptions: $e');
    }
  }

  static Future<void> _drainInitialFcmMessage() async {
    try {
      final m = await FirebaseMessaging.instance.getInitialMessage();
      if (m == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PushNavigationService.handleNotificationMap(m.data);
      });
    } catch (e) {
      debugPrint('getInitialMessage error: $e');
    }
  }

  static Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    await _fcmForegroundSub?.cancel();
    _fcmForegroundSub = null;
    await _fcmOpenedSub?.cancel();
    _fcmOpenedSub = null;
    _fcmListenersBound = false;
    _inited = false;
  }

  static Future<void> requestPermissions() async {
    if (kIsWeb) return;

    // Local permission
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
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
  // Debug: print current FCM token
  // =========================
  static Future<void> debugPrintFcmToken() async {
    try {
      final token = kIsWeb
          ? await FirebaseMessaging.instance.getToken()
          : await _fcm.getToken();
      debugPrint('FCM_TOKEN: $token');
    } catch (e) {
      debugPrint('debugPrintFcmToken error: $e');
    }
  }

  // =========================
  // FCM -> Supabase
  // =========================
  static Future<void> syncFcmTokenToSupabase() async {
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;

    if (user == null) {
      debugPrint('No session yet; skip FCM token sync');
      return;
    }

    try {
      final token =
          kIsWeb ? await FirebaseMessaging.instance.getToken() : await _fcm.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('FCM token is null/empty');
        return;
      }
      await _upsertToken(token, allowWeb: kIsWeb);
    } catch (e) {
      debugPrint('FCM getToken error: $e');
    }
  }

  static String? _lastFcmUpsertLogKey;

  static Future<void> _upsertToken(String token, {bool allowWeb = false}) async {
    if (kIsWeb && !allowWeb) return;

    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;
    if (user == null) return;

    final String platform;
    if (kIsWeb) {
      platform = 'web';
    } else {
      platform = switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'ios',
        TargetPlatform.android => 'android',
        _ => 'other',
      };
    }

    final String deviceId;
    if (kIsWeb) {
      deviceId = token.length >= 32
          ? token.substring(0, 32)
          : 'web_${token.hashCode.abs()}';
    } else {
      deviceId = await _deviceId();
    }

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

      final logKey = '${user.id}|$deviceId|${token.hashCode}';
      if (kDebugMode && _lastFcmUpsertLogKey != logKey) {
        _lastFcmUpsertLogKey = logKey;
        debugPrint('Saved FCM token user=${user.id} device=$deviceId');
      }
    } catch (e) {
      debugPrint('Supabase upsert token error: $e');
    }

    try {
      await sb.rpc('sync_user_fcm_profile_token', params: {'p_fcm_token': token});
    } catch (e) {
      debugPrint('sync_user_fcm_profile_token RPC: $e');
      try {
        await sb.from('users_profiles').update({
          'fcm_token': token,
          'fcm_token_updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('user_id', user.id);
      } catch (e2) {
        debugPrint('users_profiles fcm_token mirror error: $e2');
      }
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
  // Clear OTP notifications (badge/notification tray)
  // =========================
  static Future<void> clearOtpNotifications() async {
    if (kIsWeb) return;

    try {
      if (!_inited) await init();
      await _plugin.cancel(_otpNotificationId);
    } catch (e) {
      debugPrint('clearOtpNotifications error: $e');
    }
  }

  static int _workflowNotificationId(String? dedupeKey) {
    final h = (dedupeKey ?? DateTime.now().toIso8601String()).hashCode;
    return 92000 + (h.abs() % 7999);
  }

  /// إشعار محلي (درج الإشعارات) عندما يكون التطبيق في الخلفية — ليس لرموز OTP.
  static Future<void> showWorkflowLocalNotification({
    required String title,
    required String body,
    String? dedupeKey,
    Map<String, String>? payloadMap,
  }) async {
    if (kIsWeb) return;
    if (!_inited) await init();

    if (payloadMap != null &&
        payloadMap.containsKey('conversation_id') &&
        !await ChatNotificationPrefs.isEnabled()) {
      return;
    }

    final kind = (payloadMap?['kind'] ?? 'property').toString();
    final channelId = kind == 'support'
        ? 'chat_support'
        : kind == 'reservation'
            ? 'chat_reservation'
            : _workflowChannel.id;
    final channelName = kind == 'support'
        ? 'دعم — موثوق العقاري'
        : kind == 'reservation'
            ? 'حجوزات — موثوق العقاري'
            : _workflowChannel.name;
    final channelDesc = kind == 'support'
        ? 'رسائل الدعم'
        : kind == 'reservation'
            ? 'تنبيهات الحجز'
            : _workflowChannel.description;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDesc,
          importance: Importance.high,
        ),
      );
    }

    final payload = payloadMap == null || payloadMap.isEmpty
        ? null
        : payloadMap.entries.map((e) => '${e.key}=${e.value}').join('&');

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: androidNotificationIcon,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
    );

    await _plugin.show(
      _workflowNotificationId(dedupeKey),
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// في الخلفية: يظهر في درج الإشعارات؛ في المقدمة يُكتفى بالشريط العلوي داخل التطبيق.
  static void handleIncomingWorkflowAlert({
    required String title,
    required String body,
    String? dedupeKey,
  }) {
    if (kIsWeb) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) {
      return;
    }
    unawaited(
      showWorkflowLocalNotification(
        title: title,
        body: body,
        dedupeKey: dedupeKey,
        payloadMap: null,
      ),
    );
  }

  // =========================
  // Local OTP notification
  // =========================
  static Future<void> showOtpNotification({
    required String title,
    required String body,
    /// إذا كان `false`: إشعار مرئي/اهتزاز فقط — يُفضَّل مع [AppSoundCoordinator] لتجنب تداخل نغمة القناة مع نغمة الأصول داخل التطبيق.
    bool playChannelSound = false,
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
        playSound: playChannelSound,
        enableVibration: true,
        icon: androidNotificationIcon,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: playChannelSound,
        presentBadge: true,
      ),
    );

    await _plugin.show(
      _otpNotificationId,
      title,
      body,
      details,
    );
  }

  /// مسح رقم الشارة على أيقونة التطبيق حيث يُدعم ذلك.
  /// - **iOS:** يُنفَّذ فعلياً من [AppDelegate] عند become/resign active.
  /// - **Android:** يختلف حسب المشغّل؛ الإشعارات المقروءة تُخفّض العداد تدريجياً.
  static Future<void> clearOsApplicationIconBadge() async {
    if (kIsWeb) return;
    // نقطة توسعة لاحقة (مثل ShortcutBadger) دون اعتماد على API غير متوفر في الإصدار الحالي.
  }
}