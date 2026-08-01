import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/branding/app_branding.dart';
import '../core/notifications/hub_workflow_sound.dart';
import '../core/notifications/in_app_notification_catalog.dart';
import '../core/notifications/in_app_notification_sound.dart';
import '../core/notifications/workflow_toast_sound.dart';

/// صف واحد من `in_app_notifications` جاهز للعرض والتوجيه.
class InAppNotificationPayload {
  final String id;
  final String type;
  final String titleAr;
  final String titleEn;
  final String bodyAr;
  final String bodyEn;
  final Map<String, dynamic> rawRow;

  const InAppNotificationPayload({
    required this.id,
    required this.type,
    required this.titleAr,
    required this.titleEn,
    required this.bodyAr,
    required this.bodyEn,
    required this.rawRow,
  });

  String titleForLang(String lang) {
    final isAr = lang.toLowerCase() != 'en';
    final en = titleEn.trim().isNotEmpty;
    final ar = titleAr.trim().isNotEmpty;
    if (lang == 'en') {
      if (en) return AppBranding.normalizeUserFacing(titleEn, isAr: false);
      if (ar) return AppBranding.normalizeUserFacing(titleAr, isAr: true);
    } else {
      if (ar) return AppBranding.normalizeUserFacing(titleAr, isAr: true);
      if (en) return AppBranding.normalizeUserFacing(titleEn, isAr: false);
    }
    return AppBranding.normalizeUserFacing(
      (rawRow['title'] ?? rawRow['type'] ?? 'Notification').toString(),
      isAr: isAr,
    );
  }

  String bodyForLang(String lang) {
    final isAr = lang.toLowerCase() != 'en';
    final en = bodyEn.trim().isNotEmpty;
    final ar = bodyAr.trim().isNotEmpty;
    if (lang == 'en') {
      if (en) return AppBranding.normalizeUserFacing(bodyEn, isAr: false);
      if (ar) return AppBranding.normalizeUserFacing(bodyAr, isAr: true);
    } else {
      if (ar) return AppBranding.normalizeUserFacing(bodyAr, isAr: true);
      if (en) return AppBranding.normalizeUserFacing(bodyEn, isAr: false);
    }
    return AppBranding.normalizeUserFacing(
      (rawRow['message'] ?? rawRow['body'] ?? '').toString(),
      isAr: isAr,
    );
  }

  factory InAppNotificationPayload.fromRecord(Map<String, dynamic> row) {
    Map<String, dynamic> dataMap = {};
    final rawData = row['data'];
    if (rawData is Map) {
      dataMap = Map<String, dynamic>.from(rawData);
    } else if (rawData is String && rawData.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawData);
        if (decoded is Map) {
          dataMap = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    final titleAr =
        (dataMap['title_ar'] ?? dataMap['title'] ?? row['title'] ?? '').toString();
    final titleEn =
        (dataMap['title_en'] ?? dataMap['title'] ?? row['title'] ?? '').toString();
    final bodyAr = (dataMap['body_ar'] ??
            dataMap['body'] ??
            row['message'] ??
            row['body'] ??
            '')
        .toString();
    final bodyEn = (dataMap['body_en'] ??
            dataMap['body'] ??
            row['message'] ??
            row['body'] ??
            '')
        .toString();

    return InAppNotificationPayload(
      id: (row['id'] ?? '').toString(),
      type: (row['type'] ?? '').toString(),
      titleAr: AppBranding.normalizeUserFacing(titleAr, isAr: true),
      titleEn: AppBranding.normalizeUserFacing(titleEn, isAr: false),
      bodyAr: AppBranding.normalizeUserFacing(bodyAr, isAr: true),
      bodyEn: AppBranding.normalizeUserFacing(bodyEn, isAr: false),
      rawRow: Map<String, dynamic>.from(row),
    );
  }
}

/// شريط إشعار عائم + تنسيق أيقونة حسب النوع.
///
/// **العرض:** إشعار واحد مرئي؛ الواردات الأخرى تُصفّ في طابور (حد أقصى [kMaxQueuedToasts]).
/// **متى يظهر:** عند إدراج صف في `in_app_notifications` يطابق المستخدم (Realtime) — مستثنى أنماط OTP/تحقق.
/// **تكرار:** نفس `id` خلال ثانيتين يُهمل (debounce). عند الإغلاق أو انتهاء المؤقت يُعرض التالي مع نغمة.
class InAppNotificationHub {
  InAppNotificationHub._();

  static const int kMaxQueuedToasts = 12;

  static final ValueNotifier<InAppNotificationPayload?> toast =
      ValueNotifier<InAppNotificationPayload?>(null);

  static final List<InAppNotificationPayload> _queue = [];

  /// يُسجَّل من لوحة المستخدم لتحديث عدّاد الجرس فور وصول إشعار Realtime.
  static VoidCallback? onInboxInvalidate;

  /// مطابقة صفوف Realtime: `username` (سياسات RLS الحالية) و/أو `user_id` إن وُجد في الصف.
  static String? _sessionUsername;
  static String? _sessionUserId;

  static void setSessionUsername(String? v) {
    final s = (v ?? '').trim();
    _sessionUsername = s.isEmpty ? null : s;
  }

  static void setSessionUserId(String? v) {
    final s = (v ?? '').trim();
    _sessionUserId = s.isEmpty ? null : s;
  }

  static String? _debounceId;
  static DateTime? _debounceAt;

  /// مطابقة صف `in_app_notifications` للمستخدم الحالي (نفس منطق [onInsertRecord]).
  static bool recordMatchesSession(Map<String, dynamic>? record) {
    if (record == null) return false;
    final row = Map<String, dynamic>.from(record);
    final wantName = (_sessionUsername ?? '').trim();
    final wantUid = (_sessionUserId ?? '').trim();
    final rowUser = (row['username'] ?? '').toString().trim();
    final rowUid = (row['user_id'] ?? '').toString().trim();
    final matchesUser =
        wantUid.isNotEmpty && rowUid.isNotEmpty && rowUid == wantUid;
    final matchesName =
        wantName.isNotEmpty && rowUser.isNotEmpty && rowUser == wantName;
    return matchesUser || matchesName;
  }

  /// تحديث/حذف صف (قراءة، حذف من الويب/جهاز آخر) — يحدّث عدّاد الجرس دون Toast.
  static void onRecordUpdated(Map<String, dynamic>? record) {
    if (!recordMatchesSession(record)) return;
    onInboxInvalidate?.call();
  }

  static void onRecordDeleted(Map<String, dynamic>? record) {
    if (!recordMatchesSession(record)) return;
    onInboxInvalidate?.call();
  }

  static void dismiss() {
    toast.value = null;
    _presentNextQueued();
  }

  /// تفريغ كامل عند الخروج / تبديل الحساب — لا تُعرض إشعارات الجلسة السابقة.
  static void clearQueueAndToast() {
    _queue.clear();
    toast.value = null;
    _debounceId = null;
    _debounceAt = null;
  }

  static void _presentNextQueued() {
    if (_queue.isEmpty || toast.value != null) return;
    final next = _queue.removeAt(0);
    toast.value = next;
    playWorkflowToastSound(next.type);
  }

  /// استدعاء من Realtime عند إدراج صف جديد.
  static void onInsertRecord(Map<String, dynamic>? record) {
    if (record == null) return;

    final row = Map<String, dynamic>.from(record);
    if (!recordMatchesSession(row)) return;

    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return;

    final t = (row['type'] ?? '').toString().toLowerCase();
    if (t.contains('otp') ||
        t.contains('pin') ||
        t.contains('verify') ||
        t.contains('verification') ||
        t.contains('recovery') ||
        t.contains('mfa') ||
        t.contains('2fa')) {
      return;
    }

    final now = DateTime.now();
    if (_debounceId == id &&
        _debounceAt != null &&
        now.difference(_debounceAt!) < const Duration(seconds: 2)) {
      return;
    }
    _debounceId = id;
    _debounceAt = now;

    final payload = InAppNotificationPayload.fromRecord(row);

    if (toast.value != null) {
      if (_queue.length < kMaxQueuedToasts) {
        _queue.add(payload);
      }
    } else {
      toast.value = payload;
      // v8: إشعارات «last_call»/«expired_72h» تُشغّل نغمة تنبيه أقوى.
      _playSoundForPayload(payload);
    }
    onInboxInvalidate?.call();
  }

  static void _playSoundForPayload(InAppNotificationPayload payload) {
    try {
      final t = payload.type.toLowerCase();
      final dataRaw = payload.rawRow['data'];
      Map<String, dynamic>? data;
      if (dataRaw is Map) {
        data = Map<String, dynamic>.from(dataRaw);
      } else if (dataRaw is String && dataRaw.isNotEmpty) {
        try {
          final parsed = jsonDecode(dataRaw);
          if (parsed is Map) data = Map<String, dynamic>.from(parsed);
        } catch (_) {}
      }
      final soundHint = (data?['sound'] ?? '').toString().toLowerCase();
      // last_call أو expired_72h → استخدم نغمة الـpermitWarning (الأبرز).
      if (soundHint == 'last_call' ||
          t.contains('last_call') ||
          t.contains('expired_72h') ||
          t.contains('permit.expired') ||
          t.contains('contract.expired')) {
        playHubWorkflowSound(HubWorkflowSoundKind.permitWarning);
        return;
      }
    } catch (_) {}
    playInAppNotificationChime();
  }

  static IconData iconForType(String type, {String entityType = ''}) {
    return InAppNotificationCatalog.iconFor(
      type: type,
      entityType: entityType,
    );
  }

  static Color accentForType(String type, {String entityType = ''}) {
    return InAppNotificationCatalog.accentFor(
      type: type,
      entityType: entityType,
    );
  }
}

/// يضبطه الـ router عند فتح إشعار يحتاج تبويبات لوحة المستخدم.
class InAppDashboardDeepLink {
  InAppDashboardDeepLink._();

  static final ValueNotifier<Map<String, dynamic>?> pending =
      ValueNotifier<Map<String, dynamic>?>(null);

  static void clear() {
    pending.value = null;
  }
}
