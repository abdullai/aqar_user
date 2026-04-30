import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/users_profiles_safe_select.dart';
import 'auth_service.dart';

/// مؤسسة / فريق للمكاتب والمؤسسات والشركات العقارية.
class OrgTeamService {
  OrgTeamService(this._sb);

  final SupabaseClient _sb;

  Future<String?> ensureMyOrgUnit() async {
    try {
      final res = await _sb.rpc('ensure_my_org_unit');
      if (res == null) return null;
      return res.toString();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> myOrgContext() async {
    try {
      final raw = await _sb.rpc('my_org_context');
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (_) {}
    return null;
  }

  /// نسخة الشروط النشطة (SECURITY DEFINER على الخادم؛ يتطلب GRANT EXECUTE للمستخدم المسجّل).
  /// قبول الشروط: `acceptTerms` → RPC `accept_terms_v1` يحدّث `users_profiles.terms_version_accepted`.
  Future<Map<String, dynamic>?> activeLegalVersion() async {
    try {
      final rows = await _sb.rpc('get_active_legal_version');
      if (rows is List && rows.isNotEmpty) {
        final first = rows.first;
        if (first is Map) {
          return Map<String, dynamic>.from(
            first.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> myProfileGates() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _sb
          .from('users_profiles')
          .select('must_change_password, terms_version_accepted')
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  Future<void> acceptTerms(String version) async {
    await _sb.rpc('accept_terms_v1', params: {'p_version': version});
  }

  Future<void> ackProfileDataRevision(int target) async {
    await _sb.rpc('ack_profile_data_revision', params: {'p_target': target});
  }

  Future<Map<String, dynamic>> registerTrustedDevice() async {
    try {
      final fp = await AuthService.deviceFingerprint();
      final model = await AuthService.devicePlatformModelLabel();
      final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
      final raw = await _sb.rpc(
        'register_user_device_v2',
        params: {
          'p_device_id': fp,
          'p_platform': platform,
          'p_model_label': model,
        },
      );
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return {'ok': false, 'error': 'bad_response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<bool> revokeMyDevice(String fingerprint) async {
    try {
      await _sb.rpc(
        'revoke_my_trusted_device',
        params: {'p_device_fingerprint': fingerprint},
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> ownerRevokeMemberDevice({
    required String memberUserId,
    required String fingerprint,
  }) async {
    try {
      await _sb.rpc(
        'org_owner_revoke_member_device',
        params: {
          'p_member_user_id': memberUserId,
          'p_device_fingerprint': fingerprint,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> orgUnitForOwner() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _sb
          .from('org_units')
          .select(
            'id, account_type, base_seat_limit, purchased_extra_seats, created_at, recruit_join_code',
          )
          .eq('owner_user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  Future<int> memberCount(String orgId) async {
    try {
      final n = await _sb.rpc(
        'org_current_member_count',
        params: {'p_org_id': orgId},
      );
      if (n is int) return n;
      if (n is num) return n.toInt();
      return int.tryParse(n?.toString() ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<int> effectiveSeatLimit(String orgId) async {
    try {
      final n = await _sb.rpc(
        'org_effective_seat_limit',
        params: {'p_org_id': orgId},
      );
      if (n is int) return n;
      if (n is num) return n.toInt();
      return int.tryParse(n?.toString() ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> listMembers(String orgId) async {
    try {
      final rows = await _sb
          .from('org_memberships')
          .select(
            'user_id, member_role, permissions, status, created_at, invited_by_user_id',
          )
          .eq('org_id', orgId)
          .order('created_at');
      final list = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final ids = list.map((e) => '${e['user_id']}').toList();
      if (ids.isEmpty) return list;
      final pmap = await UsersProfilesSafeSelect.fetchProfilesByIds(
        _sb,
        ids,
        columnAttempts: UsersProfilesSafeSelect.enrichedProfileColumns,
      );
      for (final m in list) {
        final id = '${m['user_id']}';
        m['profile'] = pmap[id] ?? <String, dynamic>{};
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> listTrustedDevicesForUser(
    String userId,
  ) async {
    try {
      final rows = await _sb
          .from('user_trusted_devices')
          .select(
            'id, device_fingerprint, platform, model_label, created_at, last_seen_at, revoked_at',
          )
          .eq('user_id', userId)
          .order('last_seen_at', ascending: false);
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> activityLog(
    String orgId, {
    int limit = 80,
  }) async {
    try {
      final rows = await _sb
          .from('org_activity_log')
          .select(
            'id, actor_user_id, action, entity_type, entity_id, metadata, created_at',
          )
          .eq('org_id', orgId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> inviteMember({
    required String nationalId,
    required String tempPassword,
    Map<String, dynamic>? permissions,
  }) async {
    try {
      final res = await _sb.functions.invoke(
        'org_invite_member',
        body: {
          'national_id': nationalId.replaceAll(RegExp(r'\D'), ''),
          'temp_password': tempPassword,
          'permissions': permissions ?? <String, dynamic>{},
        },
      );
      if (res.data is Map) {
        final m = Map<String, dynamic>.from(res.data as Map);
        if (m['ok'] == true) return m;
        return {'ok': false, 'error': m['error'] ?? 'unknown'};
      }
      return {'ok': false, 'error': 'bad_response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<void> updateMemberPermissions({
    required String memberUserId,
    required Map<String, dynamic> permissions,
  }) async {
    await _sb.rpc(
      'org_update_member_permissions',
      params: {
        'p_member_user_id': memberUserId,
        'p_permissions': permissions,
      },
    );
  }

  static Map<String, dynamic>? parsePermissionsJson(String raw) {
    try {
      final v = jsonDecode(raw);
      if (v is Map) {
        return Map<String, dynamic>.from(
          v.map((k, val) => MapEntry(k.toString(), val)),
        );
      }
    } catch (_) {}
    return null;
  }

  /// رمز انضمام فريق العمل (10 أرقام) ليمنحه المدير للموظفين — يُستدعى بعد تطبيق SQL.
  Future<String?> getMyRecruitJoinCode() async {
    try {
      final raw = await _sb.rpc('org_get_my_recruit_join_code');
      if (raw == null) return null;
      final s = raw.toString().trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> submitJoinRequest({
    required String recruitCode,
    String? verificationRequestId,
  }) async {
    try {
      final params = <String, dynamic>{
        'p_recruit_code': recruitCode.replaceAll(RegExp(r'\D'), ''),
      };
      if (verificationRequestId != null && verificationRequestId.isNotEmpty) {
        final vid = int.tryParse(
          verificationRequestId.replaceAll(RegExp(r'\D'), ''),
        );
        if (vid != null) params['p_verification_request_id'] = vid;
      }
      final raw = await _sb.rpc(
        'org_submit_join_request',
        params: params,
      );
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return {'ok': false, 'error': 'bad_response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<List<Map<String, dynamic>>> listPendingJoinRequests() async {
    try {
      final raw = await _sb.rpc('org_list_pending_join_requests');
      if (raw is List) {
        return raw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// طلب انضمام معلّق للمستخدم الحالي (لبوابة ما بعد الدخول).
  Future<Map<String, dynamic>?> myPendingOrgJoinBanner() async {
    try {
      var raw = await _sb.rpc('my_pending_org_join_banner');
      if (raw == null) return null;
      if (raw is List && raw.isNotEmpty && raw.first is Map) {
        raw = raw.first;
      }
      if (raw is! Map) return null;
      final m = Map<String, dynamic>.from(
        raw.map((k, v) => MapEntry(k.toString(), v)),
      );
      if (m.isEmpty) return null;
      final rid = m['request_id']?.toString() ?? '';
      if (rid.isEmpty) return null;
      return m;
    } catch (_) {}
    return null;
  }

  /// محادثة قناة الفريق (موحّدة مع messages بعد `20260502_org_team_channel_unified_inbox.sql`).
  Future<String?> ensureOrgTeamChannelConversation(String orgId) async {
    final oid = orgId.trim();
    if (oid.isEmpty) return null;
    try {
      final raw = await _sb.rpc(
        'ensure_org_team_channel_conversation',
        params: {'p_org_id': oid},
      );
      final s = raw?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  /// محادثة 1:1 بين عضوين في نفس المؤسسة (يتطلب دالة الخادم ensure_direct_conversation).
  Future<String?> ensureDirectConversation(String peerUserId) async {
    final peer = peerUserId.trim();
    if (peer.isEmpty) return null;
    try {
      final raw = await _sb.rpc(
        'ensure_direct_conversation',
        params: {'p_peer': peer},
      );
      if (raw == null) return null;
      final s = raw.toString().trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  Future<void> setChatLastSeenHidden(bool hidden) async {
    try {
      await _sb.rpc(
        'set_chat_last_seen_hidden',
        params: {'p_hidden': hidden},
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>> decideJoinRequest({
    required String requestId,
    required bool approve,
    Map<String, dynamic>? permissions,
  }) async {
    try {
      final raw = await _sb.rpc(
        'org_decide_join_request',
        params: {
          'p_request_id': requestId,
          'p_approve': approve,
          'p_permissions': permissions ?? <String, dynamic>{},
        },
      );
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return {'ok': false, 'error': 'bad_response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// منشورات قناة الفريق — يتطلب تطبيق `20260453_org_team_channel_posts.sql`.
  Future<List<Map<String, dynamic>>> listOrgTeamChannelPosts(
    String orgId, {
    int limit = 200,
  }) async {
    final oid = orgId.trim();
    if (oid.isEmpty) return const [];
    try {
      final rows = await _sb
          .from('org_team_channel_posts')
          .select('id, created_at, org_id, author_id, body')
          .eq('org_id', oid)
          .order('created_at', ascending: false)
          .limit(limit) as List<dynamic>;
      return rows
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {}
    return const [];
  }

  Future<bool> insertOrgTeamChannelPost({
    required String orgId,
    required String body,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return false;
    final t = body.trim();
    if (t.isEmpty) return false;
    try {
      await _sb.from('org_team_channel_posts').insert({
        'org_id': orgId.trim(),
        'author_id': uid,
        'body': t,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}

