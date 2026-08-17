import 'package:supabase_flutter/supabase_flutter.dart';

/// طلبات تغيير نوع الحساب / الانضمام عبر المنصّة (`submit_account_change_request`).
class AccountSwitchService {
  AccountSwitchService(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> submitChangeRequest({
    required String requestedType,
    String? currentOrgUnitId,
    String? requestedOrganizationCode,
    String? reason,
  }) async {
    try {
      final raw = await _client.rpc(
        'submit_account_change_request',
        params: {
          'p_requested_type': requestedType,
          'p_current_org_unit_id': currentOrgUnitId,
          'p_requested_organization_code': requestedOrganizationCode,
          'p_reason': reason,
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
}
