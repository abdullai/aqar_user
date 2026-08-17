// lib/core/session/account_role_cache.dart
//
// Last-known account role (per user) to avoid bottom-nav flicker on dashboard load.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String _kPrefKey = 'account_role_cache_v2';

class AccountRoleSnapshot {
  final String userId;
  final String accountType;
  final bool verified;
  final bool orgNavResolved;
  final bool orgNavIsOwner;
  final Map<String, dynamic>? orgPermissions;

  const AccountRoleSnapshot({
    required this.userId,
    required this.accountType,
    required this.verified,
    required this.orgNavResolved,
    required this.orgNavIsOwner,
    this.orgPermissions,
  });

  static AccountRoleSnapshot? fromJson(Map<String, dynamic> m) {
    try {
      final uid = (m['uid'] ?? '').toString().trim();
      if (uid.isEmpty) return null;
      Map<String, dynamic>? op;
      final raw = m['op'];
      if (raw is Map) {
        op = Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return AccountRoleSnapshot(
        userId: uid,
        accountType: (m['at'] ?? 'user').toString(),
        verified: m['v'] == true,
        orgNavResolved: m['or'] == true,
        orgNavIsOwner: m['oo'] == true,
        orgPermissions: op,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'uid': userId,
        'at': accountType,
        'v': verified,
        'or': orgNavResolved,
        'oo': orgNavIsOwner,
        if (orgPermissions != null) 'op': orgPermissions,
      };
}

abstract final class AccountRoleCache {
  static AccountRoleSnapshot? _snapshot;

  static AccountRoleSnapshot? get snapshot => _snapshot;

  static Future<void> loadFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kPrefKey);
    if (s == null || s.isEmpty) {
      _snapshot = null;
      return;
    }
    try {
      final j = jsonDecode(s);
      if (j is Map) {
        _snapshot = AccountRoleSnapshot.fromJson(
          Map<String, dynamic>.from(
            j.map((k, v) => MapEntry(k.toString(), v)),
          ),
        );
      }
    } catch (_) {
      _snapshot = null;
    }
  }

  static Future<void> save(AccountRoleSnapshot snap) async {
    _snapshot = snap;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrefKey, jsonEncode(snap.toJson()));
  }

  static Future<void> clear() async {
    _snapshot = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kPrefKey);
  }
}
