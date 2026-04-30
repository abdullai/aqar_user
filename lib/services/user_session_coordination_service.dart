// lib/services/user_session_coordination_service.dart
//
// جلسة واحدة (آخر تسجيل دخول يفوز): يتطلب تنفيذ
// supabase/sql/20260335_user_session_and_audit.sql وتفعيل Realtime للجدول
// user_session_state من لوحة Supabase إن لزم.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/session/return_after_auth.dart';
import '../l10n/app_localizations.dart';

class UserSessionCoordinationService {
  UserSessionCoordinationService._();

  static GlobalKey<NavigatorState>? navigatorKey;

  static RealtimeChannel? _channel;
  static int? _localEpoch;

  static Future<void> afterSignIn(
    String userId, {
    String? cityHint,
    String? deviceLabel,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;

    dispose();

    final sb = Supabase.instance.client;

    try {
      final raw = await sb.rpc(
        'bump_user_session_epoch',
        params: {
          'p_city': cityHint ?? '',
          'p_device_label': deviceLabel ?? '',
        },
      );
      final epoch = raw is num
          ? raw.toInt()
          : int.tryParse(raw?.toString() ?? '') ?? 0;
      _localEpoch = epoch;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[session] bump_user_session_epoch skipped (run SQL migration?): $e',
        );
      }
      return;
    }

    unawaited(_tryAuditLogin(uid));

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
              final m = Map<String, dynamic>.from(payload.newRecord);
              final ep = (m['session_epoch'] as num?)?.toInt();
              if (ep == null || _localEpoch == null) return;
              if (ep > _localEpoch!) {
                unawaited(
                  _kickOutBecauseNewerSessionElsewhere(
                    lastCity: '${m['last_signin_city'] ?? ''}'.trim(),
                    lastDevice: '${m['last_signin_device'] ?? ''}'.trim(),
                  ),
                );
              }
            },
          )
          .subscribe();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[session] realtime subscribe failed: $e');
      }
    }
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
  }

  static String _platformLabel() {
    if (kIsWeb) return 'web';
    return describeEnum(defaultTargetPlatform);
  }

  static Future<void> _kickOutBecauseNewerSessionElsewhere({
    String lastCity = '',
    String lastDevice = '',
  }) async {
    final ctx = navigatorKey?.currentContext;
    bool? reclaim;
    if (ctx != null && ctx.mounted) {
      final l10n = AppLocalizations.of(ctx);
      final hasHint = lastCity.isNotEmpty || lastDevice.isNotEmpty;
      reclaim = await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (c) {
          final cs = Theme.of(c).colorScheme;
          final body = hasHint && l10n != null
              ? l10n.securitySessionSupersededBodyDetail(
                  lastCity.isEmpty ? '—' : lastCity,
                  lastDevice.isEmpty ? '—' : lastDevice,
                )
              : (l10n?.securitySessionSupersededBody ??
                  'Your account signed in elsewhere. This session will close.');
          final hint = l10n?.securitySessionSupersededChooseHint ??
              '• Keep using this device: makes this session active again.\n'
                  '• Sign out here: closes only this device.';
          return AlertDialog(
            title: Text(
              l10n?.securitySessionSupersededTitle ?? 'Session notice',
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    body,
                    style: TextStyle(color: cs.onSurface),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    hint,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      height: 1.45,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: Text(
                  l10n?.securitySessionSignOutThisDevice ?? 'Sign out here',
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(c).pop(true),
                child: Text(
                  l10n?.securitySessionContinueHere ?? 'Keep using this device',
                ),
              ),
            ],
          );
        },
      );
    }

    if (reclaim == true) {
      await _reclaimPrimarySessionAfterSuperseded();
      return;
    }

    try {
      final auth = Supabase.instance.client.auth;
      if (auth.currentSession != null) {
        await auth.signOut(scope: SignOutScope.local);
      }
    } catch (_) {}

    final nav = navigatorKey?.currentState;
    if (nav == null) return;

    if (_isOnLoginStack()) return;

    if (navigatorKey != null) {
      await ReturnAfterAuth.saveFromNavigatorKey(navigatorKey!);
    }
    nav.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  /// يعيد رفع epoch من هذا الجهاز فيصبح «الأحدث» وتُسجَّل الجلسات الأخرى خروجاً.
  static Future<void> _reclaimPrimarySessionAfterSuperseded() async {
    final sb = Supabase.instance.client;
    try {
      final raw = await sb.rpc(
        'bump_user_session_epoch',
        params: {
          'p_city': '',
          'p_device_label': '',
        },
      );
      final epoch = raw is num
          ? raw.toInt()
          : int.tryParse(raw?.toString() ?? '') ?? 0;
      if (epoch > 0) {
        _localEpoch = epoch;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[session] reclaim bump_user_session_epoch failed: $e');
      }
    }
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

  static void dispose() {
    try {
      _channel?.unsubscribe();
    } catch (_) {}
    _channel = null;
    _localEpoch = null;
  }
}
