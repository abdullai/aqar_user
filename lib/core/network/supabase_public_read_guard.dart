import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/session_manager.dart';
import 'supabase_anon_rest_headers.dart';

/// طلبات القراءة العامة (رئيسية/ضيف) — إزالة JWT تالف ثم إعادة محاولة واحدة.
abstract final class SupabasePublicReadGuard {
  static DateTime? _authFailureCooldownUntil;

  /// بعد 401 متكرر: لا نُعيد signOut/المحاولة لمدة قصيرة (يمنع عاصفة طلبات على الويب).
  static bool get isInAuthFailureCooldown {
    final until = _authFailureCooldownUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _authFailureCooldownUntil = null;
    return false;
  }

  static void _markAuthFailureCooldown() {
    _authFailureCooldownUntil =
        DateTime.now().add(const Duration(seconds: 60));
  }

  static void clearAuthFailureCooldown() {
    _authFailureCooldownUntil = null;
  }

  static void recordAuthFailure() => _markAuthFailureCooldown();

  static bool isAuthError(Object e) {
    if (e is PostgrestException) {
      final c = (e.code ?? '').trim();
      if (c == '401' || c == '403') return true;
      final m = e.message.toLowerCase();
      return m.contains('jwt') ||
          m.contains('unauthorized') ||
          m.contains('invalid claim');
    }
    final s = e.toString().toLowerCase();
    return s.contains('401') ||
        s.contains('unauthorized') ||
        s.contains('invalid jwt');
  }

  static Future<void> _prepareClient(SupabaseClient client) async {
    // لا تلمس جلسة مستخدم أثناء القراءة العامة إلا في وضع الضيف (انظر dropStale).
    await SupabaseAnonRestHeaders.dropStaleUserSessionIfNeeded(client);
  }

  /// عند 401 على قراءة عامة: أعد المحاولة بعد refresh إن أمكن.
  /// **لا** تمسح جلسة مستخدم — المسح كان يطلق signedOut ويعيد لـ `/login`.
  static Future<T> run<T>(
    SupabaseClient client,
    Future<T> Function() action, {
    bool preserveLoggedInSession = true,
  }) async {
    if (isInAuthFailureCooldown) {
      throw PostgrestException(
        message: 'Public read paused after auth error (cooldown)',
        code: '401',
      );
    }

    await _prepareClient(client);
    try {
      return await action();
    } catch (e) {
      if (!isAuthError(e)) rethrow;
      if (kDebugMode) {
        debugPrint('[SupabasePublicReadGuard] auth error: $e');
      }
      final session = client.auth.currentSession;
      if (session != null) {
        try {
          await client.auth
              .refreshSession()
              .timeout(const Duration(seconds: 6));
          return await action();
        } catch (_) {
          // ضيف فقط: امسح JWT التالف. مستخدم (حتى أثناء OTP) يبقى.
          if (!preserveLoggedInSession) {
            await SessionManager.clearLocalAuthSessionForPublicReads(client);
          }
        }
      }
      _markAuthFailureCooldown();
      rethrow;
    }
  }
}
