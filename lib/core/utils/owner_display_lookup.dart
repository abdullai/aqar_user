import 'package:supabase_flutter/supabase_flutter.dart';

/// جلب اسم المعلن للعرض العام: يُفضَّل [users_profiles] ثم [profiles].
/// مع RLS المقيّد بدعوة: المسوّق يرى المالك عندما يوجد صف في
/// [listing_request_invites] يربط `marketer_id` الحالي بـ `request_id` (انظر
/// `supabase/sql/20260403_rls_marketers_read_listing_request_owners.sql`).
Future<String> fetchOwnerDisplayName(
  SupabaseClient sb, {
  required String ownerUserId,
  required bool isAr,
}) async {
  final oid = ownerUserId.trim();
  if (oid.isEmpty) return '';

  try {
    final up = await sb
        .from('users_profiles')
        .select(
          'first_name_ar, fourth_name_ar, first_name_en, fourth_name_en, '
          'username, email, full_name_ar, full_name_en, full_name',
        )
        .eq('user_id', oid)
        .maybeSingle();
    if (up != null) {
      String? fn;
      String? ln;
      if (isAr) {
        fn = (up['first_name_ar'] as String?)?.trim();
        ln = (up['fourth_name_ar'] as String?)?.trim();
      } else {
        fn = (up['first_name_en'] as String?)?.trim();
        ln = (up['fourth_name_en'] as String?)?.trim();
      }
      if ((fn != null && fn.isNotEmpty) || (ln != null && ln.isNotEmpty)) {
        return '${fn ?? ''} ${ln ?? ''}'.trim();
      }
      if (isAr) {
        final a = (up['full_name_ar'] as String?)?.trim();
        if (a != null && a.isNotEmpty) return a;
      } else {
        final e = (up['full_name_en'] as String?)?.trim();
        if (e != null && e.isNotEmpty) return e;
      }
      final full = (up['full_name'] as String?)?.trim();
      if (full != null && full.isNotEmpty) return full;
      final un = (up['username'] as String?)?.trim();
      if (un != null && un.isNotEmpty) return un;
      final em = (up['email'] as String?)?.trim();
      if (em != null && em.isNotEmpty) return em;
    }
  } catch (_) {}

  try {
    final p = await sb
        .from('profiles')
        .select('full_name, phone')
        .eq('user_id', oid)
        .maybeSingle();
    if (p != null) {
      final n = (p['full_name'] ?? p['phone'])?.toString().trim() ?? '';
      if (n.isNotEmpty) return n;
    }
  } catch (_) {}

  try {
    final p = await sb
        .from('profiles')
        .select('full_name, phone')
        .eq('id', oid)
        .maybeSingle();
    if (p != null) {
      final n = (p['full_name'] ?? p['phone'])?.toString().trim() ?? '';
      if (n.isNotEmpty) return n;
    }
  } catch (_) {}

  return '';
}
