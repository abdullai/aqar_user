import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/notification_service.dart';
import '../widgets/app_logo_loading.dart';

const String kPrefPermissionsGateDone = 'permissions_gate_done';

class PermissionsGate extends StatefulWidget {
  final bool isAr;
  final VoidCallback onDone;

  const PermissionsGate({
    super.key,
    required this.isAr,
    required this.onDone,
  });

  @override
  State<PermissionsGate> createState() => _PermissionsGateState();
}

class _PermissionsGateState extends State<PermissionsGate> {
  bool _loading = false;
  String? _error;

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    _autoSkipIfDone();
  }

  Future<void> _autoSkipIfDone() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final done = sp.getBool(kPrefPermissionsGateDone) ?? false;
      if (done && mounted) widget.onDone();
    } catch (_) {}
  }

  Future<void> _markDone() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(kPrefPermissionsGateDone, true);
    } catch (_) {}
  }

  Future<void> _requestAll() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _requestNotifications();
      await _requestLocation();
      await _requestPhotos();
      await _requestCamera();

      await _markDone();

      if (!mounted) return;
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestNotifications() async {
    if (kIsWeb) {
      try {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        await NotificationService.init();
      } catch (_) {}
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      await Permission.notification.request();
    }
  }

  Future<void> _requestLocation() async {
    if (kIsWeb) {
      try {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
            timeLimit: const Duration(seconds: 10),
          );
        }
      } catch (_) {}
      return;
    }
    if (!_isMobile) return;
    await Permission.locationWhenInUse.request();
  }

  Future<void> _requestPhotos() async {
    if (!_isMobile) return;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await Permission.photos.request();
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final pPhotos = await Permission.photos.request();
      if (pPhotos.isDenied || pPhotos.isPermanentlyDenied) {
        await Permission.storage.request();
      }
    }
  }

  Future<void> _requestCamera() async {
    if (!_isMobile) return;
    await Permission.camera.request();
  }

  void _openSettings() {
    AppSettings.openAppSettings();
  }

  Future<void> _skipAction() async {
    await _markDone();
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    final title = t?.permissionsGateTitle ??
        (widget.isAr ? 'قبل أن نبدأ' : 'Before we start');
    final subtitle = kIsWeb
        ? (t?.permissionsGateWebSubtitle ??
            (widget.isAr
                ? 'على الويب يطلب المتصفح الأذونات عند الحاجة.'
                : 'On the web, the browser asks for permissions when needed.'))
        : (t?.permissionsGateSubtitle ??
            (widget.isAr
                ? 'لأفضل تجربة نطلب الإشعارات والموقع والصور والكاميرا بالترتيب.'
                : 'We ask for notifications, location, photos, and camera in order.'));
    final btn = t?.permissionsGateContinueAllow ??
        (widget.isAr ? 'متابعة والسماح' : 'Continue & Allow');
    final skipText =
        t?.permissionsGateNotNow ?? (widget.isAr ? 'ليس الآن' : 'Not now');
    final settings = t?.permissionsGateOpenSettings ??
        (widget.isAr ? 'فتح الإعدادات' : 'Open Settings');

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.verified_outlined,
                        size: 34,
                        color: Color(0xFF0F766E),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color:
                            cs.surfaceContainerHighest.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        children: [
                          _permRow(
                            icon: Icons.notifications_active_outlined,
                            title: t?.permissionsGateNotificationsTitle ??
                                (widget.isAr ? 'الإشعارات' : 'Notifications'),
                            desc: t?.permissionsGateNotificationsDesc ??
                                (widget.isAr
                                    ? 'تنبيهات الدردشة والحجوزات والعروض.'
                                    : 'Chat, bookings and offers alerts.'),
                          ),
                          if (_isMobile) ...[
                            const SizedBox(height: 10),
                            _permRow(
                              icon: Icons.location_on_outlined,
                              title: t?.permissionsGateLocationTitle ??
                                  (widget.isAr ? 'الموقع' : 'Location'),
                              desc: t?.permissionsGateLocationDesc ??
                                  (widget.isAr
                                      ? 'تحديد المواقع على الخريطة.'
                                      : 'Pick locations on the map.'),
                            ),
                          ],
                          if (_isMobile) ...[
                            const SizedBox(height: 10),
                            _permRow(
                              icon: Icons.photo_library_outlined,
                              title: t?.permissionsGatePhotosTitle ??
                                  (widget.isAr
                                      ? 'الصور/المعرض'
                                      : 'Photos/Gallery'),
                              desc: t?.permissionsGatePhotosDesc ??
                                  (widget.isAr
                                      ? 'لإرفاق صور الإعلان.'
                                      : 'Attach listing images.'),
                            ),
                            const SizedBox(height: 10),
                            _permRow(
                              icon: Icons.photo_camera_outlined,
                              title: t?.permissionsGateCameraTitle ??
                                  (widget.isAr ? 'الكاميرا' : 'Camera'),
                              desc: t?.permissionsGateCameraDesc ??
                                  (widget.isAr
                                      ? 'لالتقاط صورة مباشرة.'
                                      : 'Take a photo instantly.'),
                            ),
                          ],
                          if (_isDesktop) ...[
                            const SizedBox(height: 10),
                            Text(
                              t?.permissionsGateDesktopNote ??
                                  (widget.isAr
                                      ? 'على الكمبيوتر غالباً تُختار الصور من الملفات.'
                                      : 'On desktop, images are picked from files.'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: _loading ? null : _requestAll,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _loading
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: AppLogoLoading(compact: true, size: 22),
                              )
                            : Text(
                                btn,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _loading ? null : _skipAction,
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              skipText,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _loading ? null : _openSettings,
                            icon: const Icon(Icons.settings_outlined),
                            label: Text(
                              settings,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _permRow({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, color: const Color(0xFF0F766E)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
