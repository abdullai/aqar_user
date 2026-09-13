import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/profile/publisher_identity_prefs.dart';
import '../core/shorts/shorts_comment_guard.dart';
import '../core/utils/users_profiles_safe_select.dart';

class ShortsFeedComment {
  const ShortsFeedComment({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.userId,
    this.authorLabel = '',
  });

  final String id;
  final String body;
  final DateTime createdAt;
  final String userId;
  final String authorLabel;

  bool get mine {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    return uid.isNotEmpty && uid == userId;
  }
}

/// تعليقات مربوطة بإعلان الشورتز. الجدول البعيد يُحذف مع العقار (CASCADE).
/// إن لم يُنفَّذ SQL بعد، تُحفظ محلياً على الجهاز حتى لا تتعطل الواجهة.
abstract final class ShortsFeedCommentsService {
  static const _table = 'property_feed_comments';
  static const _localKey = 'shorts_feed_comments_v1';
  static bool? _remoteReady;

  static String targetKey({required bool isProperty, required String id}) =>
      isProperty ? 'p:$id' : 'r:$id';

  static bool _safeTargetId(String id) {
    final t = id.trim();
    if (t.length < 8 || t.length > 80) return false;
    if (t.contains(':') || t.contains('/') || t.contains('\\')) return false;
    return true;
  }

  static Future<List<ShortsFeedComment>> load({
    required bool isProperty,
    required String id,
  }) async {
    if (!_safeTargetId(id)) return const [];
    final targetId = id.trim();
    if (isProperty && await _canUseRemote()) {
      try {
        final raw = await Supabase.instance.client
            .from(_table)
            .select('id, body, created_at, user_id')
            .eq('property_id', targetId)
            .order('created_at', ascending: false)
            .limit(80);
        return _withAuthorLabels([
          for (final e in raw)
            _fromRow(Map<String, dynamic>.from(e as Map)),
        ]);
      } catch (_) {
        _remoteReady = false;
      }
    }
    return _withAuthorLabels(
      await _loadLocal(targetKey(isProperty: isProperty, id: targetId)),
    );
  }

  static Future<Map<String, int>> countsForPropertyIds(Iterable<String> ids) async {
    final out = <String, int>{};
    final list = ids
        .map((e) => e.trim())
        .where(_safeTargetId)
        .toSet();
    if (list.isEmpty) return out;

    if (await _canUseRemote()) {
      try {
        final raw = await Supabase.instance.client
            .from(_table)
            .select('property_id')
            .inFilter('property_id', list.toList());
        for (final row in raw) {
          final map = Map<String, dynamic>.from(row as Map);
          final pid = (map['property_id'] ?? '').toString();
          if (pid.isEmpty) continue;
          out[pid] = (out[pid] ?? 0) + 1;
        }
        return out;
      } catch (_) {
        _remoteReady = false;
      }
    }

    final local = await _allLocal();
    for (final id in list) {
      final n = (local[targetKey(isProperty: true, id: id)] as List?)?.length ?? 0;
      if (n > 0) out[id] = n;
    }
    return out;
  }

  static Future<Map<String, int>> countsForRequestIds(Iterable<String> ids) async {
    final out = <String, int>{};
    final local = await _allLocal();
    for (final id in ids.map((e) => e.trim()).where(_safeTargetId)) {
      final n =
          (local[targetKey(isProperty: false, id: id)] as List?)?.length ?? 0;
      if (n > 0) out[id] = n;
    }
    return out;
  }

  static Future<ShortsFeedComment?> add({
    required bool isProperty,
    required String id,
    required String body,
  }) async {
    final targetId = id.trim();
    if (!_safeTargetId(targetId)) return null;
    final text = body.trim();
    if (text.isEmpty) return null;
    if (ShortsCommentGuard.looksLikeOffAppContact(text)) return null;
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return null;
    await PublisherIdentityPrefs.instance.ensureLoaded();
    final label = PublisherIdentityPrefs.instance.resolvedPublicName(
      isAr: true,
    );
    final labelEn = PublisherIdentityPrefs.instance.resolvedPublicName(
      isAr: false,
    );
    final author = label.trim().isNotEmpty
        ? label.trim()
        : (labelEn.trim().isNotEmpty ? labelEn.trim() : '');

    if (isProperty && await _canUseRemote()) {
      try {
        final row = await Supabase.instance.client
            .from(_table)
            .insert({
              'property_id': targetId,
              'user_id': uid,
              'body': text,
            })
            .select('id, body, created_at, user_id')
            .single();
        final parsed = _fromRow(Map<String, dynamic>.from(row as Map));
        return ShortsFeedComment(
          id: parsed.id,
          body: parsed.body,
          createdAt: parsed.createdAt,
          userId: parsed.userId,
          authorLabel: author.isNotEmpty ? author : parsed.authorLabel,
        );
      } catch (_) {
        _remoteReady = false;
      }
    }

    final c = ShortsFeedComment(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      body: text,
      createdAt: DateTime.now(),
      userId: uid,
      authorLabel: author,
    );
    final key = targetKey(isProperty: isProperty, id: targetId);
    final all = await _allLocal();
    final cur = ((all[key] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    cur.insert(0, {
      'id': c.id,
      'body': c.body,
      'created_at': c.createdAt.toIso8601String(),
      'user_id': c.userId,
      'author_label': c.authorLabel,
    });
    all[key] = cur;
    final p = await SharedPreferences.getInstance();
    await p.setString(_localKey, jsonEncode(all));
    return c;
  }

  static Future<bool> _canUseRemote() async {
    if (_remoteReady == true) return true;
    if (_remoteReady == false) return false;
    try {
      await Supabase.instance.client.from(_table).select('id').limit(1);
      _remoteReady = true;
    } catch (_) {
      _remoteReady = false;
    }
    return _remoteReady == true;
  }

  static ShortsFeedComment _fromRow(Map<String, dynamic> row) {
    return ShortsFeedComment(
      id: (row['id'] ?? '').toString(),
      body: (row['body'] ?? '').toString(),
      createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.now(),
      userId: (row['user_id'] ?? '').toString(),
      authorLabel: (row['author_label'] ?? '').toString().trim(),
    );
  }

  static Future<Map<String, dynamic>> _allLocal() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_localKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final dec = jsonDecode(raw);
      if (dec is Map<String, dynamic>) return dec;
      if (dec is Map) return Map<String, dynamic>.from(dec);
    } catch (_) {}
    return <String, dynamic>{};
  }

  static Future<List<ShortsFeedComment>> _withAuthorLabels(
    List<ShortsFeedComment> rows,
  ) async {
    final visible = rows
        .where((c) => !ShortsCommentGuard.looksLikeOffAppContact(c.body))
        .toList();
    final missing = visible
        .where((c) => c.authorLabel.trim().isEmpty && c.userId.isNotEmpty)
        .map((c) => c.userId)
        .toSet();
    if (missing.isEmpty) return visible;
    Map<String, Map<String, dynamic>> profiles = {};
    try {
      profiles = await UsersProfilesSafeSelect.fetchProfilesByIds(
        Supabase.instance.client,
        missing,
        columnAttempts: const [
          'user_id,display_name,full_name,full_name_ar,full_name_en,office_name,public_name_source,username',
          'user_id,full_name,full_name_ar,username',
          'user_id,username',
        ],
      );
    } catch (_) {}
    return [
      for (final c in visible)
        c.authorLabel.trim().isNotEmpty
            ? c
            : ShortsFeedComment(
                id: c.id,
                body: c.body,
                createdAt: c.createdAt,
                userId: c.userId,
                authorLabel: _labelFromProfile(profiles[c.userId]),
              ),
    ];
  }

  static String _labelFromProfile(Map<String, dynamic>? row) {
    if (row == null) return '';
    String pick(String k) => (row[k] ?? '').toString().trim();
    final src = pick('public_name_source').toLowerCase();
    if (src == 'display' || src == 'alias') {
      final a = pick('display_name');
      if (a.isNotEmpty) return a;
    }
    for (final k in [
      'display_name',
      'office_name',
      'full_name_ar',
      'full_name_en',
      'full_name',
      'username',
    ]) {
      final v = pick(k);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static Future<List<ShortsFeedComment>> _loadLocal(String key) async {
    final all = await _allLocal();
    final list = (all[key] as List?) ?? const [];
    return list
        .map((e) => _fromRow(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  }
}
