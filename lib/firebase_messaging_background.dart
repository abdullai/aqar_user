// Top-level background handler — must stay in its own library (vm entry-point).
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'core/branding/app_branding.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // عند وجود حقل notification يرسم النظام الإشعار تلقائياً في الخلفية (Android/iOS).
  if (message.notification != null) return;

  final data = message.data;
  if (data.isEmpty) return;

  final body = (data['body'] ?? data['body_ar'] ?? '').toString().trim();
  final title = (data['title'] ?? data['title_ar'] ?? AppBranding.brandNameAr)
      .toString()
      .trim();
  if (title.isEmpty && body.isEmpty) return;

  final kind = (data['kind'] ?? 'property').toString();
  final channelId = kind == 'support'
      ? 'chat_support'
      : kind == 'reservation'
          ? 'chat_reservation'
          : 'chat_property';

  const androidInit = AndroidInitializationSettings('@drawable/ic_stat_aqar');
  const iosInit = DarwinInitializationSettings();
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(android: androidInit, iOS: iosInit),
  );

  if (defaultTargetPlatform == TargetPlatform.android) {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        channelId,
        AppBranding.brandNameAr,
        description: 'محادثات، حجوزات، وتنبيهات',
        importance: Importance.high,
      ),
    );
  }

  final id = message.messageId?.hashCode.abs() ?? DateTime.now().millisecondsSinceEpoch % 100000;

  await plugin.show(
    id,
    title.isEmpty
        ? AppBranding.brandNameAr
        : AppBranding.normalizeUserFacing(title, isAr: true),
    AppBranding.normalizeUserFacing(body, isAr: true),
    NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        AppBranding.brandNameAr,
        channelDescription: 'محادثات، حجوزات، وتنبيهات',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_stat_aqar',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
    ),
    payload: data.entries.map((e) => '${e.key}=${e.value}').join('&'),
  );
}
