import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// مفاتيح الصلاحيات الموحّدة (تطابق JSON في org_memberships.permissions).
abstract class OrgPermissionKeys {
  static const manageTeam = 'manage_team';
  static const addProperties = 'add_properties';
  static const addAds = 'add_ads';
  static const addListingRequests = 'add_listing_requests';
  static const editProperties = 'edit_properties';
  static const viewMarket = 'view_market';
  static const viewProfile = 'view_profile';
  static const accessChat = 'access_chat';
  static const editOrgSettings = 'edit_org_settings';
  static const viewAnalytics = 'view_analytics';
  static const manageSubscription = 'manage_subscription';
  static const exportData = 'export_data';
  static const inviteMembers = 'invite_members';
  static const manageChatRooms = 'manage_chat_rooms';
  static const viewMemberActivity = 'view_member_activity';

  static const viewReports = 'view_reports';

  /// كل المفاتيح الوظيفية (بدون أعلام التجميع desk / middle_nav).
  static const List<String> allPermissionKeys = [
    manageTeam,
    addProperties,
    addAds,
    addListingRequests,
    editProperties,
    viewMarket,
    viewProfile,
    accessChat,
    editOrgSettings,
    viewAnalytics,
    viewReports,
    manageSubscription,
    exportData,
    inviteMembers,
    manageChatRooms,
    viewMemberActivity,
  ];
}

/// يقرأ صلاحيات العضو الحالي مع كاش [SharedPreferences].
class OrgPermissionManager {
  OrgPermissionManager._();

  static const _kPrefix = 'org_perm_cache_v1_';

  static String _uidKey(String uid) => '$_kPrefix$uid';

  static Future<void> cacheForUser(
    String userId,
    Map<String, dynamic>? permissions,
    {bool isOwner = false}
  ) async {
    if (userId.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    if (isOwner) {
      final om = <String, dynamic>{
        for (final k in OrgPermissionKeys.allPermissionKeys) k: true,
        'desk': true,
        'middle_nav': true,
      };
      await p.setString(_uidKey(userId), jsonEncode(om));
      return;
    }
    if (permissions == null || permissions.isEmpty) {
      await p.remove(_uidKey(userId));
      return;
    }
    await p.setString(_uidKey(userId), jsonEncode(permissions));
  }

  static Future<Map<String, dynamic>?> loadCached(String userId) async {
    if (userId.isEmpty) return null;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_uidKey(userId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final d = jsonDecode(raw);
      if (d is Map) {
        return d.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return null;
  }

  static Future<void> clearUser(String userId) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_uidKey(userId));
  }

  /// مسح كل كاش الصلاحيات المحفوظ محلياً (مثلاً بعد تسجيل الخروج).
  static Future<void> clearAllCachedUsers() async {
    final p = await SharedPreferences.getInstance();
    try {
      for (final k in p.getKeys()) {
        if (k.startsWith(_kPrefix)) {
          await p.remove(k);
        }
      }
    } catch (_) {}
  }

  static bool _truthy(dynamic v) {
    if (v == true) return true;
    if (v == false || v == null) return false;
    final s = v.toString().toLowerCase();
    return s == '1' || s == 'true';
  }

  static bool can(Map<String, dynamic>? perm, String key) {
    if (perm == null) return false;
    if (_truthy(perm['all'])) return true;
    return _truthy(perm[key]);
  }

  static bool ownerOr(Map<String, dynamic>? perm, String key, {required bool isOwner}) {
    if (isOwner) return true;
    return can(perm, key);
  }
}
