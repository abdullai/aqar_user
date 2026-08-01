import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// تعارض عرض تسويق (409 من RPC).
class ListingOfferConflictException implements Exception {
  const ListingOfferConflictException();
}

/// أدوات موحّدة لمعالجة أخطاء REST/RPC مع Supabase (لا يوجد middleware عام في supabase_flutter).
abstract final class SupabaseRequestInterceptor {
  static bool isConflict(PostgrestException e) {
    final c = (e.code ?? '').trim();
    if (c == '409' || c == '23505') return true;
    final m = e.message.toLowerCase();
    return m.contains('409') ||
        m.contains('conflict') ||
        m.contains('duplicate_offer') ||
        m.contains('unique constraint') ||
        m.contains('offers_unique');
  }

  static bool looksUnauthorized(PostgrestException e) {
    final c = (e.code ?? '').trim();
    if (c == '401' || c == '403') return true;
    final m = e.message.toLowerCase();
    return m.contains('jwt') ||
        m.contains('not authorized') ||
        m.contains('unauthorized');
  }

  static bool looksServerError(PostgrestException e) {
    final c = (e.code ?? '').trim();
    return c == '500' || c == '502' || c == '503';
  }

  static String? userMessageFor(
    Object e, {
    required bool isAr,
  }) {
    if (e is ListingOfferConflictException ||
        (e is PostgrestException && isConflict(e))) {
      final m = e is PostgrestException ? e.message.toLowerCase() : '';
      if (m.contains('listing_permits_unique')) {
        return isAr
            ? 'يوجد تصريح مسجّل مسبقاً لهذا الطلب.'
            : 'A permit record already exists for this request.';
      }
      return isAr
          ? 'لديك عرض نشط بالفعل لهذا الطلب، أو سجّلت عرضاً سابقاً. حدّث الصفحة ثم أعد المحاولة.'
          : 'You already have an active or prior offer on this request. Refresh and try again.';
    }
    if (e is PostgrestException && looksServerError(e)) {
      return isAr
          ? 'تعذر تحميل البيانات من الخادم. حاول لاحقاً.'
          : 'A server error occurred. Please try again later.';
    }
    return null;
  }

  static void showIfHandled(BuildContext context, Object e, {required bool isAr}) {
    if (!context.mounted) return;
    final msg = userMessageFor(e, isAr: isAr);
    if (msg == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// إعادة المحاولة مرة واحدة بعد [refreshSession] عند خطأ يبدو كمصادقة.
  /// ضيف / بلا جلسة: لا refresh_token (كان يسبب 400 ويعطّل الإقلاع).
  /// عند فشل التحديث: لا نمسح الجلسة هنا (كان يعيد المستخدم لـ `/login`).
  static Future<T> runWithSessionRefresh<T>(
    SupabaseClient client,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      if (!looksUnauthorized(e)) rethrow;
      if (client.auth.currentSession == null) rethrow;
      try {
        await client.auth
            .refreshSession()
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        rethrow;
      }
      return await action();
    }
  }
}
