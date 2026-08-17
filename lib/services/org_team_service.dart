import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/users_profiles_safe_select.dart';
import 'auth_service.dart';

/// مؤسسة / فريق للمكاتب والمؤسسات والشركات العقارية.
class OrgTeamService {
  OrgTeamService(this._sb);

  final SupabaseClient _sb;

  /// بعد التسجيل: طلب انضمام يُنشأ عند أول جلسة مسجّلة.
  static const prefPendingSignupOrgJoinId = 'pending_signup_org_join_id_v1';
  static const prefPendingSignupOrgJoinIntro = 'pending_signup_org_join_intro_v1';

  /// معاينة منشأة برمز فال/دعوة (قبل تسجيل الدخول).
  Future<Map<String, dynamic>> orgPreviewByInviteCode(String code) async {
    try {
      final raw = await _sb.rpc(
        'org_preview_by_invite_code',
        params: {'p_code': code.trim()},
      );
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (_) {}
    return {'ok': false, 'error': 'rpc_failed'};
  }

  /// يقرأ المفتاح المحفوظ عند التسجيل ثم يُرسل طلب الانضمام مرة واحدة.
  Future<Map<String, dynamic>> consumePendingSignupOrgJoin() async {
    final p = await SharedPreferences.getInstance();
    final oid = p.getString(prefPendingSignupOrgJoinId)?.trim() ?? '';
    final intro = p.getString(prefPendingSignupOrgJoinIntro)?.trim() ?? '';
    if (oid.isEmpty) {
      return {'ok': true, 'skipped': true};
    }
    final msg = intro.isEmpty ? null : intro;
    final res = await submitJoinRequestByOrgId(orgId: oid, message: msg);
    if (res['ok'] == true) {
      await p.remove(prefPendingSignupOrgJoinId);
      await p.remove(prefPendingSignupOrgJoinIntro);
    }
    return res;
  }

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
    const timeout = Duration(seconds: 8);
    try {
      if (kIsWeb) {
        final fromTable = await _activeLegalVersionFromTable(timeout: timeout);
        if (fromTable != null) return fromTable;
      }
      final rows = await _sb
          .rpc('get_active_legal_version')
          .timeout(timeout, onTimeout: () => throw TimeoutException('rpc'));
      if (rows is List && rows.isNotEmpty) {
        final first = rows.first;
        if (first is Map) {
          return Map<String, dynamic>.from(
            first.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      }
    } catch (_) {}
    if (!kIsWeb) {
      return _activeLegalVersionFromTable(timeout: timeout);
    }
    return null;
  }

  Future<Map<String, dynamic>?> _activeLegalVersionFromTable({
    required Duration timeout,
  }) async {
    try {
      final row = await _sb
          .from('legal_documents_versions')
          .select('version, title_ar, title_en, body_ar, body_en')
          .lte('effective_at', DateTime.now().toUtc().toIso8601String())
          .order('effective_at', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(timeout, onTimeout: () => throw TimeoutException('table'));
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
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
            'id, account_type, base_seat_limit, purchased_extra_seats, created_at, recruit_join_code, fal_public_code',
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

  /// دعوة عضو (هوية + جوال) — يتطلب `20260517240000_org_team_invitations_workflow.sql`.
  Future<Map<String, dynamic>> createTeamInvitation({
    required String nationalId,
    required String mobile,
  }) async {
    try {
      final raw = await _sb.rpc(
        'org_create_team_invitation',
        params: {
          'p_national_id': nationalId.replaceAll(RegExp(r'\D'), ''),
          'p_mobile': mobile.replaceAll(RegExp(r'\D'), ''),
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

  Future<List<Map<String, dynamic>>> listTeamInvitations() async {
    try {
      final raw = await _sb.rpc('org_list_team_invitations');
      Iterable<dynamic>? rows;
      if (raw is List) {
        rows = raw;
      } else if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is List) rows = decoded;
      }
      if (rows == null) return [];
      return rows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> updateTeamInvitation({
    required String invitationId,
    required String nationalId,
    required String mobile,
  }) async {
    try {
      final raw = await _sb.rpc(
        'org_update_team_invitation',
        params: {
          'p_invitation_id': invitationId,
          'p_national_id': nationalId.replaceAll(RegExp(r'\D'), ''),
          'p_mobile': mobile.replaceAll(RegExp(r'\D'), ''),
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

  /// تحقق قبل التسجيل (بدون جلسة).
  Future<Map<String, dynamic>> verifyTeamInvitation({
    required String nationalId,
    required String mobile,
  }) async {
    try {
      final raw = await _sb.rpc(
        'org_verify_team_invitation',
        params: {
          'p_national_id': nationalId.replaceAll(RegExp(r'\D'), ''),
          'p_mobile': mobile.replaceAll(RegExp(r'\D'), ''),
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

  Future<Map<String, dynamic>> completeTeamInvitation(String invitationId) async {
    try {
      final raw = await _sb.rpc(
        'org_complete_team_invitation',
        params: {'p_invitation_id': invitationId},
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

  @Deprecated('Use createTeamInvitation instead')
  Future<Map<String, dynamic>> inviteMember({
    required String nationalId,
    required String tempPassword,
    Map<String, dynamic>? permissions,
  }) async {
    return createTeamInvitation(
      nationalId: nationalId,
      mobile: tempPassword,
    );
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
      final raw = await _sb
          .rpc('org_list_pending_join_requests')
          .timeout(const Duration(seconds: 8));
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
    String? rejectReason,
  }) async {
    try {
      final raw = await _sb.rpc(
        'org_decide_join_request',
        params: {
          'p_request_id': requestId,
          'p_approve': approve,
          'p_permissions': permissions ?? <String, dynamic>{},
          if (rejectReason != null && rejectReason.trim().isNotEmpty)
            'p_reject_reason': rejectReason.trim(),
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

  Future<List<Map<String, dynamic>>> browsePublicOrganizations({
    int limit = 40,
  }) async {
    try {
      final raw = await _sb.rpc('org_browse_public', params: {'limit_n': limit});
      if (raw is List) {
        return raw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      if (raw is String) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            return decoded
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
        } catch (_) {}
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> publicOrganizationProfile(String orgId) async {
    final id = orgId.trim();
    if (id.isEmpty) return null;
    try {
      final raw = await _sb.rpc('org_public_profile', params: {'p_org_id': id});
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> submitJoinRequestByOrgId({
    required String orgId,
    String? message,
    String? verificationRequestId,
  }) async {
    try {
      final params = <String, dynamic>{
        'p_org_id': orgId.trim(),
        'p_message': message,
      };
      if (verificationRequestId != null && verificationRequestId.isNotEmpty) {
        final vid = int.tryParse(
          verificationRequestId.replaceAll(RegExp(r'\D'), ''),
        );
        if (vid != null) params['p_verification_request_id'] = vid;
      }
      final raw = await _sb.rpc(
        'org_submit_join_request_by_org',
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

  Future<Map<String, dynamic>> renewFalLicense() async {
    try {
      final raw = await _sb.rpc('org_renew_fal_license');
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

  Future<Map<String, dynamic>> updateOrgProfile(Map<String, dynamic> patch) async {
    try {
      final raw = await _sb.rpc('org_update_profile', params: {'p_patch': patch});
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

  Future<Map<String, dynamic>> submitLeaveRequest() async {
    try {
      final raw = await _sb.rpc('org_submit_leave_request');
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

  Future<Map<String, dynamic>> decideLeaveRequest({
    required String requestId,
    required bool approve,
  }) async {
    try {
      final raw = await _sb.rpc(
        'org_decide_leave_request',
        params: {
          'p_request_id': requestId,
          'p_approve': approve,
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

  Future<Map<String, dynamic>> ownerUnbanUser(String userId) async {
    try {
      final raw = await _sb.rpc(
        'org_owner_unban_user',
        params: {'p_user_id': userId},
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

  Future<Map<String, dynamic>> ownerRemoveAlumniRow(String alumniId) async {
    try {
      final raw = await _sb.rpc(
        'org_owner_remove_alumni_row',
        params: {'p_alumni_id': alumniId},
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

  Future<Map<String, dynamic>> ownerRemoveMember(String memberUserId) async {
    try {
      final raw = await _sb.rpc(
        'org_owner_remove_member',
        params: {'p_member_user_id': memberUserId},
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

  /// يُرجع [id] المنشور عند النجاح (للمزامنة الفورية مع messages بعد الـ trigger).
  Future<String?> insertOrgTeamChannelPost({
    required String orgId,
    required String body,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    final t = body.trim();
    if (t.isEmpty) return null;
    try {
      final row = await _sb.from('org_team_channel_posts').insert({
        'org_id': orgId.trim(),
        'author_id': uid,
        'body': t,
      }).select('id').maybeSingle();
      final id = (row?['id'] ?? '').toString().trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// Sum of listings/ads created by each member (best-effort; depends on RLS).
  Future<Map<String, Map<String, int>>> fetchOrgMemberContribution(
    String orgId,
  ) async {
    final out = <String, Map<String, int>>{};
    final members = await listMembers(orgId);
    for (final m in members) {
      final id = '${m['user_id'] ?? ''}';
      if (id.isEmpty) continue;
      out[id] = {'properties': 0, 'ads': 0, 'views': 0};
    }
    if (out.isEmpty) return out;
    final ids = out.keys.toList();
    try {
      final props = await _sb
          .from('properties')
          .select('owner_id')
          .inFilter('owner_id', ids);
      for (final row in props as List<dynamic>) {
        final r = Map<String, dynamic>.from(row as Map);
        final uid = '${r['owner_id'] ?? ''}';
        if (!out.containsKey(uid)) continue;
        out[uid]!['properties'] = (out[uid]!['properties'] ?? 0) + 1;
      }
    } catch (_) {}
    try {
      final adsRows = await _sb
          .from('ads')
          .select('created_by')
          .inFilter('created_by', ids);
      for (final row in adsRows as List<dynamic>) {
        final r = Map<String, dynamic>.from(row as Map);
        final uid = '${r['created_by'] ?? ''}';
        if (!out.containsKey(uid)) continue;
        out[uid]!['ads'] = (out[uid]!['ads'] ?? 0) + 1;
      }
    } catch (_) {}
    return out;
  }

  /// آخر نشاط مسجّل لكل عضو (من org_activity_log).
  Future<Map<String, String>> fetchLatestActivitySummaryByUserIds(
    String orgId,
    List<String> userIds,
  ) async {
    final out = <String, String>{};
    if (userIds.isEmpty) return out;
    try {
      final rows = await _sb
          .from('org_activity_log')
          .select('actor_user_id, action, created_at')
          .eq('org_id', orgId)
          .inFilter('actor_user_id', userIds)
          .order('created_at', ascending: false)
          .limit(200) as List<dynamic>;
      for (final row in rows) {
        final m = Map<String, dynamic>.from(row as Map);
        final uid = '${m['actor_user_id'] ?? ''}';
        if (uid.isEmpty || out.containsKey(uid)) continue;
        final a = '${m['action'] ?? ''}';
        final t = '${m['created_at'] ?? ''}';
        out[uid] = a.isEmpty ? t : '$a · $t';
      }
    } catch (_) {}
    return out;
  }

  Future<bool> isPlatformStaffUser() async {
    try {
      final raw = await _sb.rpc('is_platform_staff');
      return raw == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> platformStaffBanUser({
    required String userId,
    required String reason,
    String banType = 'permanent',
    DateTime? banUntil,
    bool canJoinOtherOrgs = true,
    bool blocksApp = true,
  }) async {
    try {
      String? untilStr;
      if (banUntil != null) {
        untilStr =
            '${banUntil.year}-${banUntil.month.toString().padLeft(2, '0')}-${banUntil.day.toString().padLeft(2, '0')}';
      }
      final raw = await _sb.rpc(
        'platform_staff_ban_user',
        params: {
          'p_user_id': userId,
          'p_reason': reason.trim(),
          'p_ban_type': banType,
          'p_ban_until': untilStr,
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

  Future<Map<String, dynamic>> platformStaffTerminateSessions(
    String userId,
  ) async {
    try {
      final raw = await _sb.rpc(
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

