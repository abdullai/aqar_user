import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/users_profiles_safe_select.dart';

class AccountTypeService {
  static final _sb = Supabase.instance.client;

  static const _profileColumnAttempts = [
    'user_id,account_type,verification_status',
    'user_id,account_type',
    'user_id',
  ];

  static Future<Map<String, dynamic>?> myProfile() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    return UsersProfilesSafeSelect.fetchProfileById(
      _sb,
      uid,
      columnAttempts: _profileColumnAttempts,
    );
  }

  static Future<void> setAccountType({
    required String accountType,
    required String verificationStatus,
    String? officeName,
    String? licenseNo,
    String? commercialRegNo,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw 'No session';

    await _sb.from('users_profiles').update({
      'account_type': accountType,
      'verification_status': verificationStatus,
      'office_name': officeName,
      'license_no': licenseNo,
      'commercial_reg_no': commercialRegNo,
    }).eq('user_id', uid);
  }
}