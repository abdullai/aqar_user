import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/input/input_normalizers.dart';
import '../core/utils/users_profiles_safe_select.dart';

/// فحص الحقول الإلزامية بعد الدخول (بدون كسر الحسابات القديمة).
class AccountCompletionService {
  static const _marketingTypes = {
    'marketer',
    'office',
    'institution',
    'company',
  };

  static bool accountTypeNeedsUnifiedNational(String? accountType) {
    return _marketingTypes.contains((accountType ?? '').trim().toLowerCase());
  }

  static bool hasValidUnifiedNational(Map<String, dynamic>? row) {
    if (row == null) return false;
    final d = digitsOnly(
      normalizeAsciiDigits(
        (row['unified_national_number'] ?? '').toString(),
      ),
    );
    return isValidUnifiedNationalNumberDigits(d);
  }

  /// هل يجب إيقاف الدخول لاستكمال الرقم الوطني الموحّد فقط؟
  static bool needsUnifiedNationalCompletion(Map<String, dynamic>? row) {
    if (row == null) return false;
    final at = row['account_type']?.toString();
    if (!accountTypeNeedsUnifiedNational(at)) return false;
    return !hasValidUnifiedNational(row);
  }

  static Future<Map<String, dynamic>?> loadRow(SupabaseClient sb) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await UsersProfilesSafeSelect.fetchProfileById(
        sb,
        uid,
        columnAttempts: const [
          'user_id,account_type,unified_national_number,username',
          'user_id,account_type,username',
          'user_id,username',
          'user_id',
        ],
      );
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveUnifiedNational({
    required SupabaseClient sb,
    required String tenDigits700,
  }) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw 'no_session';
    final d = digitsOnly(normalizeAsciiDigits(tenDigits700));
    if (!isValidUnifiedNationalNumberDigits(d)) {
      throw 'invalid_unified_national';
    }
    await sb.from('users_profiles').update({
      'unified_national_number': d,
    }).eq('user_id', uid);
  }
}
