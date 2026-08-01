import 'compound_display_name.dart';

/// استخراج اسم العرض وآخر دخول من صف users_profiles (لتسجيل الدخول وشاشة التحقق).
///
/// ترتيب «آخر دخول» يفضّل `last_verified_login_at` (يُحدَّث بعد OTP عبر `LoginSecurityDb`).
/// انظر: `lib/core/auth/login_security_db.dart`
///
/// عند غياب صف الملف أو فشل RLS يمكن قراءة الاسم من [User.userMetadata]
/// (مثل `full_name` بعد التسجيل) وآخر دخول من [User.lastSignInAt].
class ProfileGreetingFromRow {
  ProfileGreetingFromRow._();

  /// `full_name` / `name` من بيانات المستخدم في Auth (raw_user_meta_data).
  static String? displayNameFromAuthMetadata(Map<String, dynamic>? meta) {
    if (meta == null || meta.isEmpty) return null;
    final s = (meta['full_name'] ?? meta['name'] ?? '').toString().trim();
    return s.isEmpty ? null : CompoundDisplayName.normalize(s);
  }

  static DateTime? lastSignInFromAuthString(String? iso) {
    if (iso == null || iso.trim().isEmpty) return null;
    return DateTime.tryParse(iso.trim());
  }

  static String? displayName(Map<String, dynamic> row, {required bool isAr}) {
    String pickStr(String k) => (row[k] ?? '').toString().trim();

    final alias = CompoundDisplayName.normalize(pickStr('display_name'));
    final source = pickStr('public_name_source').toLowerCase();
    final wantAlias = source == 'display';

    final arParts = [
      pickStr('first_name_ar'),
      pickStr('second_name_ar'),
      pickStr('third_name_ar'),
      pickStr('fourth_name_ar'),
    ].where((e) => e.isNotEmpty).toList();

    final enParts = [
      pickStr('first_name_en'),
      pickStr('second_name_en'),
      pickStr('third_name_en'),
      pickStr('fourth_name_en'),
    ].where((e) => e.isNotEmpty).toList();

    final arFull = pickStr('full_name_ar');
    final enFull = pickStr('full_name_en');
    final anyFull = pickStr('full_name');
    final office = pickStr('office_name');
    final accountType = pickStr('account_type').toLowerCase();

    final nameFromPartsAr = CompoundDisplayName.normalize(arParts.join(' '));
    final nameFromPartsEn = CompoundDisplayName.normalize(enParts.join(' '));

    String? pickAr() {
      if (nameFromPartsAr.isNotEmpty) return nameFromPartsAr;
      if (arFull.isNotEmpty) return CompoundDisplayName.normalize(arFull);
      if (anyFull.isNotEmpty) return CompoundDisplayName.normalize(anyFull);
      return null;
    }

    String? pickEn() {
      if (nameFromPartsEn.isNotEmpty) return nameFromPartsEn;
      if (enFull.isNotEmpty) return CompoundDisplayName.normalize(enFull);
      if (anyFull.isNotEmpty) return CompoundDisplayName.normalize(anyFull);
      return null;
    }

    String? official() {
      // للكيانات — الاسم/الصفة المعتمدة (مكتب/مؤسسة/شركة).
      const orgEntities = {'office', 'institution', 'company', 'agency'};
      if (orgEntities.contains(accountType) && office.isNotEmpty) {
        return office;
      }
      final primary = isAr ? pickAr() : pickEn();
      final secondary = isAr ? pickEn() : pickAr();
      final merged = (primary != null && primary.trim().isNotEmpty)
          ? primary.trim()
          : (secondary != null && secondary.trim().isNotEmpty)
              ? secondary.trim()
              : '';
      if (merged.isNotEmpty) return merged;
      if (office.isNotEmpty) return office;
      return null;
    }

    if (wantAlias && alias.isNotEmpty) return alias;

    final off = official();
    if (off != null && off.isNotEmpty) return off;
    if (alias.isNotEmpty) return alias;
    return null;
  }

  static DateTime? lastLoginAt(Map<String, dynamic> row) {
    for (final key in const [
      'last_verified_login_at',
      'last_login_at',
      'last_seen_at',
      'last_sign_in_at',
    ]) {
      final lastRaw = row[key];
      if (lastRaw is DateTime) return lastRaw;
      if (lastRaw != null) {
        final d = DateTime.tryParse(lastRaw.toString());
        if (d != null) return d;
      }
    }
    return null;
  }
}
