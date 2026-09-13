import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/compound_display_name.dart';
import '../utils/phone_display.dart';
import '../utils/users_profiles_safe_select.dart';

/// هوية الدعم: الاسم الرباعي والجوال المحلي — بلا UUID في العرض.
abstract final class SupportIdentity {
  static String quadNameFromMap(Map<String, dynamic>? row, {required bool isAr}) {
    if (row == null) return '';
    final arParts = [
      '${row['first_name_ar'] ?? ''}',
      '${row['second_name_ar'] ?? ''}',
      '${row['third_name_ar'] ?? ''}',
      '${row['fourth_name_ar'] ?? ''}',
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final enParts = [
      '${row['first_name_en'] ?? ''}',
      '${row['second_name_en'] ?? ''}',
      '${row['third_name_en'] ?? ''}',
      '${row['fourth_name_en'] ?? ''}',
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final ar = CompoundDisplayName.normalize(
      arParts.isNotEmpty
          ? arParts.join(' ')
          : '${row['full_name_ar'] ?? row['full_name'] ?? ''}',
    );
    final en = CompoundDisplayName.normalize(
      enParts.isNotEmpty
          ? enParts.join(' ')
          : '${row['full_name_en'] ?? row['full_name'] ?? ''}',
    );
    final picked = isAr
        ? (ar.isNotEmpty ? ar : en)
        : (en.isNotEmpty ? en : ar);
    if (picked.isEmpty) return '';
    if (CompoundDisplayName.looksLikeNumericUsername(picked)) return '';
    return picked;
  }

  static String phoneFromMap(Map<String, dynamic>? row) {
    if (row == null) return '';
    return PhoneDisplay.localTenDigits('${row['phone'] ?? ''}');
  }

  static Future<({String name, String phone})> load(
    SupabaseClient sb,
    String userId, {
    required bool isAr,
  }) async {
    if (userId.trim().isEmpty) return (name: '', phone: '');
    final row = await UsersProfilesSafeSelect.fetchProfileById(
      sb,
      userId,
      columnAttempts: UsersProfilesSafeSelect.structuredLegalNameColumns,
    );
    return (
      name: quadNameFromMap(row, isAr: isAr),
      phone: phoneFromMap(row),
    );
  }
}
