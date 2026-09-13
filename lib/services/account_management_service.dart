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

  Future<Map<String, dynamic>> myStaffProfile() async {
    try {
      final raw = await _client.rpc('get_my_platform_staff_profile');
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (_) {}
    return const {'ok': false, 'is_staff': false};
  }

  Future<List<Map<String, dynamic>>> listListingReports({int limit = 80}) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_list_listing_reports',
        params: {'p_limit': limit},
      );
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<Map<String, dynamic>> reviewListingReport({
    required String reportId,
    required String decision,
    String? note,
  }) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_review_listing_report',
        params: {
          'p_report_id': reportId,
          'p_decision': decision,
          'p_note': note,
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

  Future<List<Map<String, dynamic>>> directory({
    String q = '',
    String filter = 'all',
  }) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_directory',
        params: {'p_q': q, 'p_limit': 80, 'p_filter': filter},
      );
      if (raw is Map && raw['ok'] == true && raw['rows'] is List) {
        return (raw['rows'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<List<Map<String, dynamic>>> teamList() async {
    try {
      final raw = await _client.rpc('platform_staff_team_list');
      if (raw is Map && raw['ok'] == true && raw['rows'] is List) {
        return (raw['rows'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<Map<String, dynamic>> grantOps({
    required String userId,
    bool support = true,
    bool moderate = false,
    bool finance = false,
    bool grant = false,
    bool active = true,
    bool ads = false,
    bool promo = false,
    bool ban = false,
    bool teamComms = false,
  }) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_grant_ops',
        params: {
          'p_user_id': userId,
          'p_support': support,
          'p_moderate': moderate,
          'p_finance': finance,
          'p_grant': grant,
          'p_active': active,
          'p_ads': ads,
          'p_promo': promo,
          'p_ban': ban,
          'p_team_comms': teamComms,
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

  Future<Map<String, dynamic>> revokeOps(String userId) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_revoke_ops',
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

  Future<Map<String, dynamic>> setFee({
    required String feeKey,
    required double amountSar,
  }) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_set_fee',
        params: {'p_fee_key': feeKey, 'p_amount_sar': amountSar},
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

  Future<Map<String, dynamic>> upsertLoginAd({
    required String titleAr,
    required String titleEn,
    String subtitleAr = '',
    String subtitleEn = '',
    String? imageUrl,
    String? linkUrl,
    String? id,
    String placement = 'login',
  }) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_upsert_login_ad',
        params: {
          'p_title_ar': titleAr,
          'p_title_en': titleEn,
          'p_subtitle_ar': subtitleAr,
          'p_subtitle_en': subtitleEn,
          'p_image_url': imageUrl,
          'p_link_url': linkUrl,
          'p_id': id,
          'p_placement': placement,
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

  Future<Map<String, dynamic>> sendNotice({
    required String userId,
    required String titleAr,
    required String titleEn,
    required String bodyAr,
    required String bodyEn,
  }) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_send_notice',
        params: {
          'p_user_id': userId,
          'p_title_ar': titleAr,
          'p_title_en': titleEn,
          'p_body_ar': bodyAr,
          'p_body_en': bodyEn,
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

  Future<Map<String, dynamic>> myMarketProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const {};
    try {
      final row = await _client
          .from('users_profiles')
          .select(
            'user_id, username, account_type, full_name, full_name_ar, full_name_en, office_name, display_name, public_name_source, first_name_ar, second_name_ar, third_name_ar, fourth_name_ar, first_name_en, second_name_en, third_name_en, fourth_name_en',
          )
          .eq('user_id', uid)
          .maybeSingle();
      if (row != null) {
        return Map<String, dynamic>.from(row);
      }
    } catch (_) {}
    return const {};
  }

  Future<List<Map<String, dynamic>>> listAudit({int limit = 120}) async {
    try {
      final rows = await _client
          .from('platform_staff_audit_log')
          .select(
            'id, staff_id, action, target_table, target_id, payload, created_at',
          )
          .order('created_at', ascending: false)
          .limit(limit);
      return rows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {}
    return const [];
  }

  Future<List<Map<String, dynamic>>> listPromos() async {
    try {
      final raw = await _client.rpc('platform_staff_list_promos');
      if (raw is Map && raw['ok'] == true && raw['rows'] is List) {
        return (raw['rows'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<Map<String, dynamic>> upsertPromo({
    required String code,
    String kind = 'percent_off',
    required double value,
    String titleAr = '',
    String titleEn = '',
    bool active = true,
    DateTime? validFrom,
    DateTime? validTo,
    int? maxRedemptions,
    String? campaignKey,
  }) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_upsert_promo',
        params: {
          'p_code': code,
          'p_kind': kind,
          'p_value': value,
          'p_title_ar': titleAr,
          'p_title_en': titleEn,
          'p_active': active,
          'p_valid_from': validFrom?.toUtc().toIso8601String(),
          'p_valid_to': validTo?.toUtc().toIso8601String(),
          'p_max_redemptions': maxRedemptions,
          'p_campaign_key': campaignKey,
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

  Future<List<Map<String, dynamic>>> promoRedemptions(
    String promotionId, {
    String q = '',
  }) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_promo_redemptions',
        params: {
          'p_id': promotionId,
          'p_q': q,
        },
      );
      if (raw is Map && raw['ok'] == true && raw['rows'] is List) {
        return (raw['rows'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<Map<String, dynamic>> suggestedPlans(String userId) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_suggested_plans',
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

  Future<Map<String, dynamic>> grantPlan({
    required String userId,
    required String planId,
    int months = 12,
  }) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_grant_plan',
        params: {
          'p_user_id': userId,
          'p_plan_id': planId,
          'p_months': months,
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

  Future<Map<String, dynamic>> broadcastTeam({
    required String titleAr,
    required String titleEn,
    required String bodyAr,
    required String bodyEn,
  }) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_broadcast_team',
        params: {
          'p_title_ar': titleAr,
          'p_title_en': titleEn,
          'p_body_ar': bodyAr,
          'p_body_en': bodyEn,
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

  Future<Map<String, dynamic>> userIntel() async {
    try {
      final raw = await _client.rpc('platform_staff_user_intel');
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (_) {}
    return const {'ok': false};
  }

  Future<List<Map<String, dynamic>>> watchList(String kind) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_watch_list',
        params: {'p_kind': kind, 'p_limit': 40},
      );
      if (raw is Map && raw['ok'] == true && raw['rows'] is List) {
        return (raw['rows'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<Map<String, dynamic>> notifyWatch({
    required String kind,
    required String titleAr,
    required String titleEn,
    required String bodyAr,
    required String bodyEn,
  }) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_notify_watch',
        params: {
          'p_kind': kind,
          'p_title_ar': titleAr,
          'p_title_en': titleEn,
          'p_body_ar': bodyAr,
          'p_body_en': bodyEn,
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

  Future<Map<String, dynamic>> patchProfile({
    required String userId,
    String? fullNameAr,
    String? fullNameEn,
    String? phone,
    String? nationalId,
    String? officeName,
    String? licenseNo,
  }) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_patch_profile',
        params: {
          'p_user_id': userId,
          'p_full_name_ar': fullNameAr,
          'p_full_name_en': fullNameEn,
          'p_phone': phone,
          'p_national_id': nationalId,
          'p_office_name': officeName,
          'p_license_no': licenseNo,
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

  Future<List<Map<String, dynamic>>> listCampaigns() async {
    try {
      final raw = await _client.rpc('platform_staff_list_campaigns');
      if (raw is Map && raw['ok'] == true && raw['rows'] is List) {
        return (raw['rows'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<Map<String, dynamic>> upsertCampaign({
    required String titleAr,
    required String titleEn,
    required String bodyAr,
    required String bodyEn,
    String? mediaUrl,
    String deepRoute = 'user_dashboard',
    String accountType = '',
    String targetQ = '',
    DateTime? startsAt,
    DateTime? endsAt,
    bool sendAll = false,
    String kind = 'broadcast',
  }) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_upsert_campaign',
        params: {
          'p_title_ar': titleAr,
          'p_title_en': titleEn,
          'p_body_ar': bodyAr,
          'p_body_en': bodyEn,
          'p_media_url': mediaUrl,
          'p_deep_route': deepRoute,
          'p_account_type': accountType,
          'p_target_q': targetQ,
          'p_starts_at': (startsAt ?? DateTime.now()).toUtc().toIso8601String(),
          'p_ends_at': endsAt?.toUtc().toIso8601String(),
          'p_send_all': sendAll,
          'p_kind': kind,
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

  Future<Map<String, dynamic>> dispatchCampaign(String id) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_dispatch_campaign',
        params: {'p_id': id},
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

  Future<void> runDueCampaigns() async {
    try {
      await _client.rpc('platform_staff_run_due_campaigns');
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> teamTime() async {
    try {
      final raw = await _client.rpc('platform_staff_team_time');
      if (raw is Map && raw['ok'] == true && raw['rows'] is List) {
        _teamTimeUsersOnline = raw['users_online'] is num
            ? (raw['users_online'] as num).toInt()
            : int.tryParse('${raw['users_online'] ?? 0}') ?? 0;
        return (raw['rows'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  int _teamTimeUsersOnline = 0;
  int get lastUsersOnlineCount => _teamTimeUsersOnline;

  Future<Map<String, dynamic>> billingWatch() async {
    try {
      final raw = await _client.rpc('platform_staff_billing_watch');
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (_) {}
    return const {'ok': false};
  }

  Future<Map<String, dynamic>> campaignReceipts(String id) async {
    try {
      final raw = await _client.rpc(
        'platform_staff_campaign_receipts',
        params: {'p_id': id},
      );
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
    return const {'ok': false};
  }
}
