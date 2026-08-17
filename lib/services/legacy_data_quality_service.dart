import 'package:supabase_flutter/supabase_flutter.dart';

class LegacyDataQualityService {
  LegacyDataQualityService(this.sb);

  final SupabaseClient sb;

  String? get _uid => sb.auth.currentUser?.id;

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static bool _truthy(dynamic v) {
    if (v is bool) return v;
    final s = _s(v).toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  static bool _hasArabic(String s) => RegExp(r'[\u0600-\u06FF]').hasMatch(s);
  static bool _hasLatin(String s) => RegExp(r'[A-Za-z]').hasMatch(s);
  static bool _digitsOnly(String s) => RegExp(r'^[0-9]+$').hasMatch(s);

  static bool invalidArabicName(String s) {
    final v = s.trim();
    return v.isEmpty || _digitsOnly(v) || !_hasArabic(v);
  }

  static bool invalidEnglishName(String s) {
    final v = s.trim();
    return v.isEmpty || _digitsOnly(v) || _hasArabic(v) || !_hasLatin(v);
  }

  static List<String> splitNameParts(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return const ['', '', '', ''];
    return [
      parts[0],
      parts.length > 1 ? parts[1] : '',
      parts.length > 2 ? parts.sublist(2, parts.length - 1).join(' ') : '',
      parts.length > 1 ? parts.last : parts.first,
    ];
  }

  Future<Map<String, dynamic>?> currentUserProfileIssue() async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final row = await sb
          .from('v_aqar_data_quality_users')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      final m = Map<String, dynamic>.from(row);
      final ar = _s(m['full_name_ar'] ?? m['full_name']);
      final en = _s(m['full_name_en']);
      final hasIssue = _truthy(m['incomplete_english_name']) ||
          _truthy(m['incomplete_arabic_name']) ||
          invalidEnglishName(en) ||
          invalidArabicName(ar);
      return hasIssue ? m : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> currentUserPropertyIssues() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final rows = await sb
          .from('v_aqar_data_quality_properties')
          .select()
          .eq('owner_id', uid)
          .eq('has_missing_card_data', true)
          .limit(25);
      final issues = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      final ids =
          issues.map((r) => _s(r['id'])).where((id) => id.isNotEmpty).toList();
      if (ids.isEmpty) return issues;
      final details = await sb
          .from('properties')
          .select('id,title,city,price,area,owner_id,status')
          .eq('owner_id', uid)
          .inFilter('id', ids);
      final byId = <String, Map<String, dynamic>>{
        for (final e in (details as List))
          _s((e as Map)['id']): Map<String, dynamic>.from(e),
      };
      return issues
          .map((r) => {...r, ...?byId[_s(r['id'])]})
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> currentUserListingRequestIssues() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final rows = await sb
          .from('v_aqar_data_quality_listing_requests')
          .select()
          .eq('owner_id', uid)
          .eq('has_missing_request_data', true)
          .limit(25);
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<bool> hasCurrentUserRepairIssues() async {
    final profile = await currentUserProfileIssue();
    if (profile != null) return true;
    final props = await currentUserPropertyIssues();
    if (props.isNotEmpty) return true;
    final requests = await currentUserListingRequestIssues();
    return requests.isNotEmpty;
  }

  Future<void> saveProfileNames({
    required String fullNameAr,
    required String fullNameEn,
  }) async {
    final uid = _uid;
    if (uid == null) throw 'no_session';
    if (invalidArabicName(fullNameAr)) throw 'invalid_arabic_name';
    if (invalidEnglishName(fullNameEn)) throw 'invalid_english_name';

    final arParts = splitNameParts(fullNameAr);
    final enParts = splitNameParts(fullNameEn);
    await sb.from('users_profiles').update({
      'full_name': fullNameAr.trim(),
      'full_name_ar': fullNameAr.trim(),
      'full_name_en': fullNameEn.trim(),
      'first_name_ar': arParts[0],
      'second_name_ar': arParts[1],
      'third_name_ar': arParts[2],
      'fourth_name_ar': arParts[3],
      'first_name_en': enParts[0],
      'second_name_en': enParts[1],
      'third_name_en': enParts[2],
      'fourth_name_en': enParts[3],
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', uid);
  }

  Future<void> savePropertyCardData({
    required String propertyId,
    required String title,
    required String city,
    required String price,
    required String area,
  }) async {
    final uid = _uid;
    if (uid == null) throw 'no_session';
    final parsedPrice = double.tryParse(price.trim());
    final parsedArea = double.tryParse(area.trim());
    if (propertyId.trim().isEmpty ||
        title.trim().isEmpty ||
        city.trim().isEmpty ||
        parsedPrice == null ||
        parsedPrice <= 0 ||
        parsedArea == null ||
        parsedArea <= 0) {
      throw 'invalid_property_data';
    }
    await sb
        .from('properties')
        .update({
          'title': title.trim(),
          'city': city.trim(),
          'price': parsedPrice,
          'area': parsedArea,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', propertyId.trim())
        .eq('owner_id', uid);
  }

  Future<void> saveListingRequestData({
    required String requestId,
    required String title,
    required String city,
    required String price,
  }) async {
    final uid = _uid;
    if (uid == null) throw 'no_session';
    final parsedPrice = double.tryParse(price.trim());
    if (requestId.trim().isEmpty ||
        title.trim().isEmpty ||
        city.trim().isEmpty ||
        parsedPrice == null ||
        parsedPrice <= 0) {
      throw 'invalid_request_data';
    }
    await sb
        .from('listing_requests')
        .update({
          'title': title.trim(),
          'city': city.trim(),
          'price': parsedPrice,
          'request_price': parsedPrice,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', requestId.trim())
        .eq('owner_id', uid);
  }
}
