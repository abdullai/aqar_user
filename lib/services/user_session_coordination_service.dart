// lib/services/user_session_coordination_service.dart
//
// تنبيه «جلسة أخرى» فقط عندما يدخل نفس الحساب من تثبيت/جهاز مختلف.
// تحديث الصفحة أو استعادة الجلسة على نفس التثبيت لا يرفع epoch ولا يظهر الحوار.
// SQL: supabase/sql/20260923_session_other_device_notice.sql

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth/safe_sign_out_service.dart';
import '../core/security/install_device_identity.dart';
import '../core/session/web_visibility.dart';
import '../core/utils/date_helper.dart';
import '../l10n/app_localizations.dart';
import 'auth_service.dart';
import 'compliance_audit_service.dart';
import 'fast_login_service.dart';
import 'user_install_session_service.dart';

class UserSessionCoordinationService {
  UserSessionCoordinationService._();

  static GlobalKey<NavigatorState>? navigatorKey;

  static RealtimeChannel? _channel;
  static Timer? _webEpochPoll;
  static int? _localEpoch;
  static String? _boundUid;
  static bool _dialogOpen = false;
  static int? _dialogForEpoch;

  static const _selectCols =
      'session_epoch,last_signin_city,last_signin_device,'
      'last_signin_install_id,last_signin_at,last_signin_method,last_signin_platform';

  static Future<void> afterSignIn(
    String userId, {
    String? cityHint,
    String? deviceLabel,
    bool forceBump = false,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;

    disposeKeepPrefs();

    final sb = Supabase.instance.client;
    _boundUid = uid;

    final install = await InstallDeviceIdentity.key();
    final localEpoch = await _readLocalEpoch(uid);
    _localEpoch = localEpoch;

    final hints = await UserInstallSessionService.sessionHintsForBump();
    final city = (cityHint ?? hints.city ?? '').trim();
    final label = (deviceLabel ?? hints.label ?? '').trim();
    final platform = hints.platform;
    final method = await FastLoginService.lastLoginMethod();
    final consumedFresh =
        await FastLoginService.consumeFreshCredentialLogin();
    final wantBump = forceBump || consumedFresh;

    _RemoteSessionRow? remote;
    try {
      remote = await _fetchRemote(sb, uid);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[session] fetch user_session_state: $e');
      }
    }

    final sameInstall = remote != null &&
        ((remote.installId.isNotEmpty && remote.installId == install) ||
            (remote.installId.isEmpty &&
                (remote.device.isEmpty || remote.device == label)));
    final alreadyWinner = sameInstall &&
        localEpoch != null &&
      remote.epoch == localEpoch &&
        (remote.installId.isEmpty || remote.installId == install);

    if (remote == null) {
      await _bumpAndStore(
        uid: uid,
        city: city,
        label: label,
        installId: install,
        method: method,
        platform: platform,
      );
    } else if (wantBump && !alreadyWinner) {
      await _bumpAndStore(
        uid: uid,
        city: city,
        label: label,
        installId: install,
        method: method,
        platform: platform,
      );
    } else if (sameInstall) {
      _localEpoch = remote.epoch;
      await _writeLocalEpoch(uid, remote.epoch);
    } else if (remote.epoch > (localEpoch ?? 0)) {
      unawaited(_kickOutBecauseNewerSessionElsewhere(remote));
    } else {
      _localEpoch = remote.epoch;
      await _writeLocalEpoch(uid, remote.epoch);
    }

    unawaited(_tryAuditLogin(uid));

    if (kIsWeb) {
      _startWebSessionEpochPolling(sb, uid);
      return;
    }

    try {
      _channel = sb
          .channel('user_session_$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'user_session_state',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: uid,
            ),
            callback: (payload) {
              _onSessionEpochRow(Map<String, dynamic>.from(payload.newRecord));
            },
          )
          .subscribe();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[session] realtime subscribe failed: $e');
      }
    }
  }

  static Future<_RemoteSessionRow?> _fetchRemote(
    SupabaseClient sb,
    String uid,
  ) async {
    try {
      final row = await sb
          .from('user_session_state')
          .select(_selectCols)
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      return _RemoteSessionRow.fromMap(Map<String, dynamic>.from(row));
    } catch (_) {
      final row = await sb
          .from('user_session_state')
          .select('session_epoch,last_signin_city,last_signin_device')
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      return _RemoteSessionRow.fromMap(Map<String, dynamic>.from(row));
    }
  }

  static void _onSessionEpochRow(Map<String, dynamic> m) {
    final remote = _RemoteSessionRow.fromMap(m);
    unawaited(_handleRemoteRow(remote));
  }

  static Future<void> _handleRemoteRow(_RemoteSessionRow remote) async {
    if (_localEpoch == null) return;
    final install = await InstallDeviceIdentity.key();
    if (remote.installId.isNotEmpty) {
      if (remote.installId == install) {
        if (remote.epoch != _localEpoch) {
          _localEpoch = remote.epoch;
          final uid = _boundUid;
          if (uid != null) await _writeLocalEpoch(uid, remote.epoch);
        }
        return;
      }
    } else {
      final myLabel = await AuthService.devicePlatformModelLabel();
      if (remote.device.isEmpty || remote.device == myLabel) {
        if (remote.epoch != _localEpoch) {
          _localEpoch = remote.epoch;
          final uid = _boundUid;
          if (uid != null) await _writeLocalEpoch(uid, remote.epoch);
        }
        return;
      }
    }
    if (remote.epoch > _localEpoch!) {
      unawaited(_kickOutBecauseNewerSessionElsewhere(remote));
    }
  }

  static void _startWebSessionEpochPolling(SupabaseClient sb, String uid) {
    _webEpochPoll?.cancel();
    Future<void> poll() async {
      try {
        final remote = await _fetchRemote(sb, uid);
        if (remote == null) return;
        await _handleRemoteRow(remote);
      } catch (_) {}
    }

    unawaited(poll());
    _webEpochPoll = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(poll());
    });
  }

  static Future<void> _tryAuditLogin(String uid) async {
    try {
      await Supabase.instance.client.from('user_login_audit').insert({
        'user_id': uid,
        'event': 'sign_in',
        'platform': _platformLabel(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
    unawaited(
      ComplianceAuditService.instance.log('auth.login', {
        'platform': _platformLabel(),
      }),
    );
  }

  static String _platformLabel() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  static Future<void> _kickOutBecauseNewerSessionElsewhere(
    _RemoteSessionRow remote,
  ) async {
    if (_dialogOpen) return;
    if (_dialogForEpoch == remote.epoch) return;
    if (_isOnLoginStack()) return;

    final ctx = navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) return;

    _dialogOpen = true;
    _dialogForEpoch = remote.epoch;
    if (kIsWeb) setWebDocumentScrollLocked(true);

    bool? reclaim;
    try {
      reclaim = await showGeneralDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        barrierLabel: 'session-notice',
        barrierColor: Colors.black.withValues(alpha: 0.55),
        useRootNavigator: true,
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (c, _, __) {
          return _SessionSupersededDialog(remote: remote);
        },
      );
    } finally {
      if (kIsWeb) setWebDocumentScrollLocked(false);
      _dialogOpen = false;
    }

    if (reclaim == true) {
      await _reclaimPrimarySessionAfterSuperseded();
      return;
    }

    final navKey = navigatorKey;
    if (navKey == null) return;
    await SafeSignOutService.signOutAndNavigateToLoginFromNavigator(
      navKey,
      logoutReason: 'session_superseded',
    );
  }

  static Future<void> _reclaimPrimarySessionAfterSuperseded() async {
    final uid = _boundUid ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final hints = await UserInstallSessionService.sessionHintsForBump();
    final method = await FastLoginService.lastLoginMethod();
    await _bumpAndStore(
      uid: uid,
      city: hints.city ?? '',
      label: hints.label ?? '',
      installId: hints.installId,
      method: method,
      platform: hints.platform,
    );
  }

  static Future<void> _bumpAndStore({
    required String uid,
    required String city,
    required String label,
    required String installId,
    required String method,
    required String platform,
  }) async {
    final sb = Supabase.instance.client;
    try {
      final raw = await sb.rpc(
        'bump_user_session_epoch',
        params: {
          'p_city': city,
          'p_device_label': label,
          'p_install_id': installId,
          'p_login_method': method,
          'p_platform': platform,
        },
      );
      final epoch = raw is num
          ? raw.toInt()
          : int.tryParse(raw?.toString() ?? '') ?? 0;
      if (epoch > 0) {
        _localEpoch = epoch;
        await _writeLocalEpoch(uid, epoch);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[session] bump with install params failed, fallback: $e');
      }
      try {
        final raw = await sb.rpc(
          'bump_user_session_epoch',
          params: {
            'p_city': city,
            'p_device_label': label,
          },
        );
        final epoch = raw is num
            ? raw.toInt()
            : int.tryParse(raw?.toString() ?? '') ?? 0;
        if (epoch > 0) {
          _localEpoch = epoch;
          await _writeLocalEpoch(uid, epoch);
        }
      } catch (e2) {
        if (kDebugMode) {
          debugPrint('[session] bump_user_session_epoch skipped: $e2');
        }
      }
    }
  }

  static String _epochPref(String uid) => 'user_session_epoch_$uid';

  static Future<int?> _readLocalEpoch(String uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getInt(_epochPref(uid));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeLocalEpoch(String uid, int epoch) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_epochPref(uid), epoch);
    } catch (_) {}
  }

  static bool _isOnLoginStack() {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) return false;
    final name = ModalRoute.of(ctx)?.settings.name ?? '';
    return name == '/' ||
        name == '/login' ||
        name == '/entryChoice' ||
        name == '/gate' ||
        name == '/fastLogin' ||
        name == '/verify' ||
        name == '/passwordSetup' ||
        name == '/deviceManagement';
  }

  static void disposeKeepPrefs() {
    _webEpochPoll?.cancel();
    _webEpochPoll = null;
    try {
      _channel?.unsubscribe();
    } catch (_) {}
    _channel = null;
  }

  static void dispose() {
    disposeKeepPrefs();
    _localEpoch = null;
    _boundUid = null;
    _dialogOpen = false;
    _dialogForEpoch = null;
  }
}

class _RemoteSessionRow {
  const _RemoteSessionRow({
    required this.epoch,
    required this.city,
    required this.device,
    required this.installId,
    required this.method,
    required this.platform,
    this.at,
  });

  final int epoch;
  final String city;
  final String device;
  final String installId;
  final String method;
  final String platform;
  final DateTime? at;

  factory _RemoteSessionRow.fromMap(Map<String, dynamic> m) {
    DateTime? at;
    final rawAt = m['last_signin_at'];
    if (rawAt != null) {
      at = DateTime.tryParse(rawAt.toString());
    }
    return _RemoteSessionRow(
      epoch: (m['session_epoch'] as num?)?.toInt() ?? 0,
      city: '${m['last_signin_city'] ?? ''}'.trim(),
      device: '${m['last_signin_device'] ?? ''}'.trim(),
      installId: '${m['last_signin_install_id'] ?? ''}'.trim(),
      method: '${m['last_signin_method'] ?? ''}'.trim(),
      platform: '${m['last_signin_platform'] ?? ''}'.trim(),
      at: at,
    );
  }
}

class _SessionSupersededDialog extends StatelessWidget {
  const _SessionSupersededDialog({required this.remote});

  final _RemoteSessionRow remote;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isAr = Localizations.localeOf(context).languageCode != 'en';

    final kind = _kindLabel(l10n, remote.platform, remote.device);
    final method = _methodLabel(l10n, remote.method);
    final when = remote.at != null
        ? DateHelper.fmtCivilDateTime(
            remote.at!.toLocal(),
            isAr: isAr,
            withSeconds: true,
          )
        : '—';
    final where = remote.city.isEmpty ? '—' : remote.city;
    final device = remote.device.isEmpty ? '—' : remote.device;

    Widget field(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: isAr ? 108 : 118,
              child: Text(
                label,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Material(
            color: cs.surface,
            elevation: 8,
            borderRadius: BorderRadius.circular(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: cs.error.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.security_rounded,
                        size: 32,
                        color: cs.error,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n?.securitySessionSupersededTitle ??
                          (isAr ? 'تنبيه جلسة' : 'Session notice'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n?.securitySessionSupersededBody ??
                          (isAr
                              ? 'تم تسجيل الدخول إلى حسابك من جهاز أو متصفح آخر.'
                              : 'Your account signed in from another device.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Column(
                        children: [
                          field(
                            l10n?.securitySessionFieldKind ??
                                (isAr ? 'نوع الدخول' : 'Sign-in type'),
                            kind,
                          ),
                          field(
                            l10n?.securitySessionFieldMethod ??
                                (isAr ? 'ماهية الدخول' : 'Sign-in method'),
                            method,
                          ),
                          field(
                            l10n?.securitySessionFieldWhen ??
                                (isAr ? 'الوقت والتاريخ' : 'Date and time'),
                            when,
                          ),
                          field(
                            l10n?.securitySessionFieldWhere ??
                                (isAr ? 'المكان' : 'Location'),
                            where,
                          ),
                          field(
                            l10n?.securitySessionFieldDevice ??
                                (isAr ? 'الجهاز' : 'Device'),
                            device,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n?.securitySessionSupersededChooseHint ??
                          (isAr
                              ? '• الاستمرار على هذا الجهاز: تبقى هنا وتُسجَّل الجلسات الأخرى خروجاً.\n• تسجيل الخروج من هنا: يُغلق هذا الجهاز فقط.'
                              : '• Keep using this device: stay signed in here and sign out other sessions.\n• Sign out here: close this device only.'),
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        height: 1.45,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context, rootNavigator: true)
                                .pop(false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              l10n?.securitySessionSignOutThisDevice ??
                                  (isAr
                                      ? 'تسجيل الخروج من هنا'
                                      : 'Sign out here'),
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context, rootNavigator: true)
                                .pop(true),
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              l10n?.securitySessionContinueHere ??
                                  (isAr
                                      ? 'الاستمرار على هذا الجهاز'
                                      : 'Keep using this device'),
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _kindLabel(
    AppLocalizations? l10n,
    String platform,
    String device,
  ) {
    final p = platform.toLowerCase();
    final d = device.toLowerCase();
    final isWeb = p.contains('web') ||
        d.startsWith('web:') ||
        d.contains('chrome') ||
        d.contains('safari') ||
        d.contains('firefox') ||
        d.contains('edge') ||
        d.contains('opera');
    final webMobile = p.contains('web_mobile') ||
        (isWeb &&
            (d.contains('android') ||
                d.contains('ios') ||
                d.contains('iphone') ||
                d.contains('mobile')));
    if (webMobile) {
      return l10n?.securitySessionKindWebMobile ?? 'Web — mobile browser';
    }
    if (isWeb && (p.contains('web_windows') || d.contains('windows'))) {
      return l10n?.securitySessionKindWebWindows ?? 'Web — Windows browser';
    }
    if (isWeb) {
      return l10n?.securitySessionKindWebDesktop ?? 'Web — desktop browser';
    }
    return l10n?.securitySessionKindApp ?? 'Device app';
  }

  static String _methodLabel(AppLocalizations? l10n, String method) {
    final m = method.trim().toLowerCase();
    if (m.contains('pin')) {
      return l10n?.securitySessionMethodPin ?? 'PIN';
    }
    if (m.contains('bio') || m.contains('face') || m.contains('finger')) {
      return l10n?.securitySessionMethodBiometric ?? 'Biometrics';
    }
    if (m.contains('otp') || m.contains('nafath')) {
      return l10n?.securitySessionMethodOtp ?? 'Verification code';
    }
    if (m.contains('password') || m.contains('pass')) {
      return l10n?.securitySessionMethodPassword ?? 'Password';
    }
    return l10n?.securitySessionMethodOther ?? 'Signed in';
  }
}
