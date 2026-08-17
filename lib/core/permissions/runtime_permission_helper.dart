import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';

/// طلب إذن عند الحاجة (بعد بوابة الإقلاع) مع حوار يوجّه لإعدادات النظام.
abstract final class RuntimePermissionHelper {
  static Future<bool> ensurePhotos(
    BuildContext context, {
    required AppLocalizations t,
  }) async {
    if (kIsWeb) return true;
    if (!_isMobile) return true;
    final s = await _photosStatus();
    if (s.isGranted || s.isLimited) return true;
    final req = await _requestPhotos();
    if (req.isGranted || req.isLimited) return true;
    if (!context.mounted) return false;
    await _showRationale(
      context,
      title: t.permissionRationalePhotosTitle,
      body: t.permissionRationalePhotosBody,
      openSettingsLabel: t.permissionsGateOpenSettings,
    );
    return false;
  }

  static Future<bool> ensureCamera(
    BuildContext context, {
    required AppLocalizations t,
  }) async {
    if (kIsWeb) return true;
    if (!_isMobile) return true;
    final s = await Permission.camera.status;
    if (s.isGranted) return true;
    final req = await Permission.camera.request();
    if (req.isGranted) return true;
    if (!context.mounted) return false;
    await _showRationale(
      context,
      title: t.permissionRationaleCameraTitle,
      body: t.permissionRationaleCameraBody,
      openSettingsLabel: t.permissionsGateOpenSettings,
    );
    return false;
  }

  static Future<bool> ensureLocation(
    BuildContext context, {
    required AppLocalizations t,
  }) async {
    if (kIsWeb) return true;
    if (!_isMobile) return true;
    var s = await Permission.locationWhenInUse.status;
    if (s.isGranted) return true;
    s = await Permission.locationWhenInUse.request();
    if (s.isGranted) return true;
    if (!context.mounted) return false;
    await _showRationale(
      context,
      title: t.permissionRationaleLocationTitle,
      body: t.permissionRationaleLocationBody,
      openSettingsLabel: t.permissionsGateOpenSettings,
    );
    return false;
  }

  static Future<bool> ensureNotifications(
    BuildContext context, {
    required AppLocalizations t,
  }) async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final s = await Permission.notification.status;
      if (s.isGranted) return true;
      final req = await Permission.notification.request();
      if (req.isGranted) return true;
    }
    if (!context.mounted) return false;
    await _showRationale(
      context,
      title: t.permissionRationaleNotificationsTitle,
      body: t.permissionRationaleNotificationsBody,
      openSettingsLabel: t.permissionsGateOpenSettings,
    );
    return false;
  }

  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<PermissionStatus> _photosStatus() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return Permission.photos.status;
    }
    final p = await Permission.photos.status;
    if (p.isGranted || p.isLimited) return p;
    return Permission.storage.status;
  }

  static Future<PermissionStatus> _requestPhotos() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return Permission.photos.request();
    }
    final p = await Permission.photos.request();
    if (p.isGranted || p.isLimited) return p;
    return Permission.storage.request();
  }

  static Future<void> _showRationale(
    BuildContext context, {
    required String title,
    required String body,
    required String openSettingsLabel,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              AppSettings.openAppSettings();
            },
            child: Text(openSettingsLabel),
          ),
        ],
      ),
    );
  }
}
