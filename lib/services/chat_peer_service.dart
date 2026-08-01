import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/profile_greeting_from_row.dart';
import '../core/utils/users_profiles_safe_select.dart';

/// جلب بيانات الطرف الآخر في الدردشة (من `users_profiles`).
abstract final class ChatPeerService {
  static String _s(dynamic v) => (v ?? '').toString().trim();

  static String displayName(Map<String, dynamic>? row, bool isAr) {
    if (row == null) return '';
    final m = Map<String, dynamic>.from(row);
    final d = ProfileGreetingFromRow.displayName(m, isAr: isAr)?.trim();
    if (d != null && d.isNotEmpty) return d;
    final alt =
        ProfileGreetingFromRow.displayName(m, isAr: !isAr)?.trim();
    if (alt != null && alt.isNotEmpty) return alt;
    final ar = _s(row['full_name_ar']);
    final en = _s(row['full_name_en']);
    final fn = _s(row['full_name']);
    if (isAr) {
      if (ar.isNotEmpty) return ar;
      if (fn.isNotEmpty) return fn;
      if (en.isNotEmpty) return en;
    } else {
      if (en.isNotEmpty) return en;
      if (fn.isNotEmpty) return fn;
      if (ar.isNotEmpty) return ar;
    }
    final u = _s(row['username']);
    if (u.isNotEmpty) return u;
    return isAr ? 'شريكنا العقاري' : 'Our partner';
  }

  static String accountTypeLabel(String? raw, bool isAr) {
    final t = (raw ?? '').toString().trim().toLowerCase();
    if (t.isEmpty) return isAr ? 'حساب' : 'Account';
    switch (t) {
      case 'marketer':
      case 'marketer_pro':
        return isAr ? 'مسوّق عقاري' : 'Marketer';
      case 'owner':
        return isAr ? 'مالك' : 'Owner';
      case 'user':
        return isAr ? 'مستخدم' : 'User';
      default:
        return t;
    }
  }

  static DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  /// نص «آخر ظهور» مثل واتساب (يعتمد على عمود chat_last_seen_at بعد migration).
  static String formatChatLastSeen(Map<String, dynamic>? row, bool isAr) {
    final dt = _parseTs(row?['chat_last_seen_at']);
    if (dt == null) {
      return isAr
          ? 'لم يُحدَّث وقت الظهور بعد — يمكنك المراسلة في أي وقت'
          : 'No last-seen yet — you can still message anytime';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(d).inDays;
    String t;
    try {
      t = DateFormat.Hm().format(dt);
    } catch (_) {
      t =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff == 0) {
      return isAr ? 'آخر ظهور اليوم $t' : 'Last seen today at $t';
    }
    if (diff == 1) {
      return isAr ? 'آخر ظهور أمس' : 'Last seen yesterday';
    }
    try {
      final dateStr = DateFormat.yMMMd(isAr ? 'ar' : 'en').format(dt);
      return isAr ? 'آخر ظهور $dateStr' : 'Last seen $dateStr';
    } catch (_) {
      final dateStr =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      return isAr ? 'آخر ظهور $dateStr' : 'Last seen $dateStr';
    }
  }

  /// متصل الآن (نبض حديث) أو آخر ظهور، مع احترام إخفاء الظهور.
  /// عند عدم وجود بيانات (قبل أول استعلام): لا نُظهر «جارٍ التحميل…» —
  /// يُترك للواجهة قرار الإخفاء أو عرض حالة افتراضية لتجنّب اللحظة المزعجة.
  ///
  /// [fallbackTimestamp] يُستخدم لعرض «آخر تحديث» نسبة لتاريخ نشاط آخر
  /// (مثل تاريخ تحديث الطلب العقاري) إذا لم يكن لدينا بيانات ظهور حقيقية.
  static String formatPresenceLine(
    Map<String, dynamic>? row,
    bool isAr, {
    DateTime? fallbackTimestamp,
  }) {
    String fmtFallback(DateTime dt) {
      final local = dt.toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final d = DateTime(local.year, local.month, local.day);
      final diff = today.difference(d).inDays;
      String t;
      String full;
      try {
        t = DateFormat.Hm().format(local);
        full = DateFormat.yMMMd(isAr ? 'ar' : 'en').add_Hm().format(local);
      } catch (_) {
        t =
            '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
        full =
            '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $t';
      }
      if (diff == 0) {
        return isAr ? 'آخر ظهور اليوم $t' : 'Last seen today at $t';
      }
      if (diff == 1) {
        return isAr ? 'آخر ظهور أمس $t' : 'Last seen yesterday at $t';
      }
      return isAr ? 'آخر ظهور $full' : 'Last seen $full';
    }

    if (row == null) {
      if (fallbackTimestamp != null) {
        return fmtFallback(fallbackTimestamp.toLocal());
      }
      return isAr ? 'لا يوجد ظهور حديث' : 'No recent activity';
    }
    // تلميح الخادم من RPC `get_user_presence_summary` — أدق من حساب
    // العميل وحده عند تأخّر Realtime.
    if (row['_online_now_hint'] == true) {
      return isAr ? 'متصل الآن' : 'Online';
    }
    final hidden = row['chat_last_seen_hidden'] == true;
    final dt = _parseTs(row['chat_last_seen_at']);
    // متصل الآن إذا كانت آخر نبضة خلال 60 ثانية — متناسب مع نبضة العميل
    // كل ~20 ثانية ونافذة الخادم 90 ثانية.
    final recent = dt != null &&
        DateTime.now().difference(dt) < const Duration(seconds: 60);
    if (hidden) {
      if (recent) {
        return isAr ? 'متصل الآن' : 'Online';
      }
      return isAr
          ? 'يخفي وقت الظهور — يمكنك مراسلته في أي وقت'
          : 'Last seen hidden — you can still message anytime';
    }
    if (recent) {
      return isAr ? 'متصل الآن' : 'Online';
    }
    if (dt != null) {
      return formatChatLastSeen(row, isAr);
    }
    if (fallbackTimestamp != null) {
      return fmtFallback(fallbackTimestamp.toLocal());
    }
    return isAr ? 'لا يوجد ظهور حديث' : 'No recent activity';
  }

  /// تلخيص تقييمات لعدة مستخدمين (أفضل لقوائم العروض).
  static Future<Map<String, ({double avg, int count})>> fetchRatingSummariesForUserIds(
    SupabaseClient sb,
    Iterable<String> userIds,
  ) async {
    final ids = userIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (ids.isEmpty) return {};
    final entries = await Future.wait(
      ids.map((id) async => MapEntry(id, await fetchRatingSummary(sb, id))),
    );
    return Map.fromEntries(entries);
  }

  static Future<({double avg, int count})> fetchRatingSummary(
    SupabaseClient sb,
    String userId,
  ) async {
    if (userId.isEmpty) return (avg: 0.0, count: 0);
    try {
      final res = await sb.rpc(
        'get_peer_rating_summary',
        params: {'p_user_id': userId},
      );
      if (res is List && res.isNotEmpty && res.first is Map) {
        final m = Map<String, dynamic>.from(res.first as Map);
        final a = (m['avg_stars'] as num?)?.toDouble() ?? 0;
        final c = (m['rating_count'] as num?)?.toInt() ?? 0;
        return (avg: a, count: c);
      }
    } catch (_) {}
    return (avg: 0.0, count: 0);
  }

  static Future<int?> fetchMyStarsForPeer(
    SupabaseClient sb,
    String ratedUserId,
  ) async {
    final me = sb.auth.currentUser?.id;
    if (me == null || me.isEmpty || ratedUserId.isEmpty) return null;
    try {
      final row = await sb
          .from('user_peer_ratings')
          .select('stars')
          .eq('rater_user_id', me)
          .eq('rated_user_id', ratedUserId)
          .maybeSingle();
      return (row?['stars'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  static Future<void> upsertPeerRating(
    SupabaseClient sb, {
    required String ratedUserId,
    required int stars,
  }) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null || uid.isEmpty || ratedUserId.isEmpty) return;
    if (uid == ratedUserId) return;
    final s = stars.clamp(1, 5);
    await sb.from('user_peer_ratings').upsert(
      {
        'rater_user_id': uid,
        'rated_user_id': ratedUserId,
        'stars': s,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'rater_user_id,rated_user_id',
    );
  }

  static Future<Map<String, dynamic>?> fetchProfile(
    SupabaseClient sb,
    String userId,
  ) async {
    if (userId.isEmpty) return null;
    return UsersProfilesSafeSelect.fetchProfileById(
      sb,
      userId,
      columnAttempts: UsersProfilesSafeSelect.enrichedProfileColumns,
    );
  }

  /// دفعة لقائمة المحادثات (صورة + اسم).
  static Future<Map<String, Map<String, dynamic>>> fetchProfilesBatch(
    SupabaseClient sb,
    List<String> userIds,
  ) async {
    final ids = userIds.where((e) => e.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};
    return UsersProfilesSafeSelect.fetchProfilesByIds(
      sb,
      ids,
      columnAttempts: UsersProfilesSafeSelect.enrichedProfileColumns,
    );
  }
}
