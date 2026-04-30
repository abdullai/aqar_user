/// استخراج اسم العرض وآخر دخول من صف users_profiles (لتسجيل الدخول وشاشة التحقق).
///
/// عند غياب صف الملف أو فشل RLS يمكن قراءة الاسم من [User.userMetadata]
/// (مثل `full_name` بعد التسجيل) وآخر دخول من [User.lastSignInAt].
class ProfileGreetingFromRow {
  ProfileGreetingFromRow._();

  /// `full_name` / `name` من بيانات المستخدم في Auth (raw_user_meta_data).
  static String? displayNameFromAuthMetadata(Map<String, dynamic>? meta) {
    if (meta == null || meta.isEmpty) return null;
    final s = (meta['full_name'] ?? meta['name'] ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  static DateTime? lastSignInFromAuthString(String? iso) {
    if (iso == null || iso.trim().isEmpty) return null;
    return DateTime.tryParse(iso.trim());
  }

  static String? displayName(Map<String, dynamic> row, {required bool isAr}) {
    String pickStr(String k) => (row[k] ?? '').toString().trim();

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

    final nameFromPartsAr = arParts.join(' ');
    final nameFromPartsEn = enParts.join(' ');

    String? pickAr() {
      if (nameFromPartsAr.isNotEmpty) return nameFromPartsAr;
      if (arFull.isNotEmpty) return arFull;
      if (anyFull.isNotEmpty) return anyFull;
      return null;
    }

    String? pickEn() {
      if (nameFromPartsEn.isNotEmpty) return nameFromPartsEn;
      if (enFull.isNotEmpty) return enFull;
      if (anyFull.isNotEmpty) return anyFull;
      return null;
    }

    // لغة الواجهة أولاً، ثم العكس (كثيراً ما يُحفظ الاسم بجهة واحدة فقط عند التسجيل).
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

  static DateTime? lastLoginAt(Map<String, dynamic> row) {
    for (final key in const [
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
