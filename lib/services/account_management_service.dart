import 'package:supabase_flutter/supabase_flutter.dart';

/// حظر المنصّة، موظفو المنصّة، وإنهاء جلسات المستخدمين (للطاقم فقط).
class AccountManagementService {
  AccountManagementService(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>?> getMyPlatformBan() async {
    try {
      final raw = await _client.rpc('get_my_platform_ban');
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<bool> isPlatformStaff() async {
    try {
      final raw = await _client.rpc('is_platform_staff');
      return raw == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> platformBanUser({
    required String userId,
    required String reason,
    String banType = 'permanent',
    DateTime? banUntil,
    bool canJoinOtherOrgs = true,
    bool blocksApp = true,
  }) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_ban_user',
        params: {
          'p_user_id': userId,
          'p_reason': reason.trim(),
          'p_ban_type': banType,
          'p_ban_until': banUntil != null
              ? '${banUntil.year}-${banUntil.month.toString().padLeft(2, '0')}-${banUntil.day.toString().padLeft(2, '0')}'
              : null,
          'p_can_join_other_orgs': canJoinOtherOrgs,
          'p_blocks_app': blocksApp,
        },
      );
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
    return {'ok': false, 'error': 'bad_response'};
  }

  Future<Map<String, dynamic>> platformLiftBan(String userId) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_lift_ban',
        params: {'p_user_id': userId},
      );
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
    return {'ok': false, 'error': 'bad_response'};
  }

  Future<Map<String, dynamic>> platformTerminateUserSessions(
    String userId,
  ) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_terminate_user_sessions',
        params: {'p_user_id': userId},
      );
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
    return {'ok': false, 'error': 'bad_response'};
  }
}
