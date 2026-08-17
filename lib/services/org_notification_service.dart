import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

/// إشعار محلي + تنبيه قصير عند وصول طلب انضمام جديد.
class OrgNotificationService {
  OrgNotificationService._();

  static AudioPlayer? _player;

  /// تشغيل نغمة قصيرة (يتخطى الويب تلقائياً؛ على الأجهزة يستخدم سِلَمّة خفيفة).
  static Future<void> playJoinRequestChime() async {
    if (kIsWeb) return;
    try {
      _player ??= AudioPlayer();
      await _player!.stop();
      await _player!.play(AssetSource('sounds/in_app_chime.wav'));
    } catch (_) {}
  }

  static Future<void> notifyOwnerNewJoinRequest({
    String? dedupeKey,
  }) async {
    if (kIsWeb) return;
    await NotificationService.showWorkflowLocalNotification(
      title: 'طلب انضمام جديد',
      body: 'راجع طلبات الانضمام في «إدارتي».',
      dedupeKey: dedupeKey,
      payloadMap: const {'kind': 'org_join'},
    );
  }

  /// إشعار فوري + نغمة عند ارتفاع عدد الطلبات المعلّقة.
  static Future<void> signalNewPendingJoinRequest({String? dedupeKey}) async {
    await Future.wait<void>([
      notifyOwnerNewJoinRequest(dedupeKey: dedupeKey),
      playJoinRequestChime(),
    ]);
  }

  /// واجهة للمستخدم بعد قبول انضمامه (يُستدعى من الشاشات عند اختفاء البوابة).
  static Future<void> notifyApplicantJoinApproved({String? dedupeKey}) async {
    if (kIsWeb) return;
    await NotificationService.showWorkflowLocalNotification(
      title: 'تم قبول الانضمام',
      body: 'يمكنك الآن استخدام ميزات الفريق حسب صلاحياتك.',
      dedupeKey: dedupeKey,
      payloadMap: const {'kind': 'org_join_approved'},
    );
  }

  static Future<void> notifyApplicantJoinRejected({
    String? reason,
    String? dedupeKey,
  }) async {
    if (kIsWeb) return;
    final r = (reason ?? '').trim();
    await NotificationService.showWorkflowLocalNotification(
      title: 'تم رفض طلب الانضمام',
      body: r.isEmpty
          ? 'راجع إشعاراتك أو تواصل مع مدير المنشأة.'
          : r,
      dedupeKey: dedupeKey,
      payloadMap: const {'kind': 'org_join_rejected'},
    );
  }
}
