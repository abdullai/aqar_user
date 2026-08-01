import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../input/input_normalizers.dart';
import '../utils/compound_display_name.dart';

/// مصدر الاسم الظاهر للآخرين.
enum PublicNameSource { official, display }

/// مصدر رقم الجوال الظاهر للآخرين.
enum PublicPhoneSource { primary, secondary, hidden }

/// تفضيلات هوية الناشر (اسم معتمد / مستعار، جوال، حضور على البطاقات).
/// يُزامَن مع `users_profiles` عند توفر الأعمدة، مع احتياطي محلي.
class PublisherIdentityPrefs {
  PublisherIdentityPrefs._();
  static final PublisherIdentityPrefs instance = PublisherIdentityPrefs._();

  static const _kNameSrc = 'publisher_public_name_source_v1';
  static const _kPhoneSrc = 'publisher_public_phone_source_v1';
  static const _kPresence = 'publisher_publish_presence_on_cards_v1';
  static const _kAlias = 'publisher_display_alias_v1';
  static const _kSecondary = 'publisher_secondary_phone_v1';

  bool _loaded = false;
  PublicNameSource nameSource = PublicNameSource.official;
  PublicPhoneSource phoneSource = PublicPhoneSource.primary;
  bool publishPresenceOnCards = true;
  String displayAlias = '';
  String secondaryPhone = '';
  String primaryPhone = '';
  String officialNameAr = '';
  String officialNameEn = '';
  String officeName = '';
  String accountType = '';
  bool _dbColumnsAvailable = true;

  bool get isLoaded => _loaded;
  bool get isOrgEntity {
    const org = {'office', 'institution', 'company', 'agency'};
    return org.contains(accountType.trim().toLowerCase());
  }

  String? get _uid {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  Future<void> ensureLoaded({Map<String, dynamic>? profileRow}) async {
    if (_loaded && profileRow == null) return;
    await reload(profileRow: profileRow);
  }

  Future<void> reload({Map<String, dynamic>? profileRow}) async {
    final p = await SharedPreferences.getInstance();
    final uid = (_uid ?? '').trim();
    final suffix = uid.isEmpty ? '' : '__$uid';

    nameSource = _parseNameSource(p.getString('$_kNameSrc$suffix'));
    phoneSource = _parsePhoneSource(p.getString('$_kPhoneSrc$suffix'));
    publishPresenceOnCards = p.getBool('$_kPresence$suffix') ?? true;
    displayAlias = (p.getString('$_kAlias$suffix') ?? '').trim();
    secondaryPhone = digitsOnly(
      normalizeAsciiDigits(p.getString('$_kSecondary$suffix') ?? ''),
    );

    Map<String, dynamic>? row = profileRow;
    if (row == null && uid.isNotEmpty) {
      row = await _fetchProfile(uid);
    }
    if (row != null) {
      _applyRow(row);
    }
    _loaded = true;
  }

  void _applyRow(Map<String, dynamic> row) {
    String pick(String k) => (row[k] ?? '').toString().trim();
    accountType = pick('account_type').toLowerCase();
    officeName = pick('office_name');
    primaryPhone = digitsOnly(normalizeAsciiDigits(pick('phone')));
    final sec = digitsOnly(normalizeAsciiDigits(pick('secondary_phone')));
    if (sec.length >= 10) secondaryPhone = sec;

    final alias = pick('display_name');
    if (alias.isNotEmpty) displayAlias = alias;

    final ns = pick('public_name_source');
    if (ns.isNotEmpty) nameSource = _parseNameSource(ns);

    final ps = pick('public_phone_source');
    if (ps.isNotEmpty) phoneSource = _parsePhoneSource(ps);

    if (row.containsKey('publish_presence_on_cards')) {
      publishPresenceOnCards = row['publish_presence_on_cards'] == true;
    }

    officialNameAr = _composeOfficial(row, ar: true);
    officialNameEn = _composeOfficial(row, ar: false);
  }

  static String _composeOfficial(Map<String, dynamic> row, {required bool ar}) {
    String pick(String k) => (row[k] ?? '').toString().trim();
    final office = pick('office_name');
    final at = pick('account_type').toLowerCase();
    const org = {'office', 'institution', 'company', 'agency'};
    if (org.contains(at) && office.isNotEmpty) return office;

    final parts = ar
        ? [
            pick('first_name_ar'),
            pick('second_name_ar'),
            pick('third_name_ar'),
            pick('fourth_name_ar'),
          ]
        : [
            pick('first_name_en'),
            pick('second_name_en'),
            pick('third_name_en'),
            pick('fourth_name_en'),
          ];
    final joined = CompoundDisplayName.normalize(
      parts.where((e) => e.isNotEmpty).join(' '),
    );
    if (joined.isNotEmpty) return joined;
    final full = CompoundDisplayName.normalize(
      pick(ar ? 'full_name_ar' : 'full_name_en'),
    );
    if (full.isNotEmpty) return full;
    return CompoundDisplayName.normalize(pick('full_name'));
  }

  /// الاسم المعتمد للمعاملات الرسمية.
  String officialName({required bool isAr}) {
    final primary = isAr ? officialNameAr : officialNameEn;
    final secondary = isAr ? officialNameEn : officialNameAr;
    if (primary.trim().isNotEmpty) return primary.trim();
    if (secondary.trim().isNotEmpty) return secondary.trim();
    if (officeName.isNotEmpty) return officeName;
    return '';
  }

  /// الاسم المستعار (إن وُجد).
  String aliasName({required bool isAr}) {
    final a = CompoundDisplayName.normalize(displayAlias);
    if (a.isNotEmpty) return a;
    return '';
  }

  /// الاسم الظاهر حسب المصدر المختار.
  String resolvedPublicName({required bool isAr}) {
    if (nameSource == PublicNameSource.display) {
      final a = aliasName(isAr: isAr);
      if (a.isNotEmpty) return a;
    }
    final o = officialName(isAr: isAr);
    if (o.isNotEmpty) return o;
    return aliasName(isAr: isAr);
  }

  /// رقم الجوال الظاهر حسب المصدر.
  String? resolvedPublicPhone() {
    switch (phoneSource) {
      case PublicPhoneSource.hidden:
        return null;
      case PublicPhoneSource.secondary:
        if (secondaryPhone.length >= 10) return secondaryPhone;
        return primaryPhone.length >= 10 ? primaryPhone : null;
      case PublicPhoneSource.primary:
        return primaryPhone.length >= 10 ? primaryPhone : null;
    }
  }

  Future<void> setNameSource(PublicNameSource v) async {
    nameSource = v;
    await _persistLocal();
    await _patchDb({'public_name_source': v.name});
  }

  Future<void> setPhoneSource(PublicPhoneSource v) async {
    phoneSource = v;
    await _persistLocal();
    await _patchDb({'public_phone_source': v.name});
  }

  Future<void> setPublishPresenceOnCards(bool v) async {
    publishPresenceOnCards = v;
    await _persistLocal();
    await _patchDb({'publish_presence_on_cards': v});
  }

  Future<void> saveDisplayAlias(String raw) async {
    final n = CompoundDisplayName.normalize(raw);
    displayAlias = n;
    await _persistLocal();
    await _patchDb({'display_name': n.isEmpty ? null : n});
  }

  Future<void> saveSecondaryPhone(String raw) async {
    var d = digitsOnly(normalizeAsciiDigits(raw));
    if (d.startsWith('966') && d.length >= 12) {
      d = '0${d.substring(3)}';
    } else if (d.startsWith('5') && d.length == 9) {
      d = '0$d';
    }
    if (d.isNotEmpty && (!d.startsWith('05') || d.length != 10)) {
      throw 'invalid_phone';
    }
    secondaryPhone = d;
    await _persistLocal();
    await _patchDb({'secondary_phone': d.isEmpty ? null : d});
  }

  Future<void> _persistLocal() async {
    final p = await SharedPreferences.getInstance();
    final uid = (_uid ?? '').trim();
    final suffix = uid.isEmpty ? '' : '__$uid';
    await p.setString('$_kNameSrc$suffix', nameSource.name);
    await p.setString('$_kPhoneSrc$suffix', phoneSource.name);
    await p.setBool('$_kPresence$suffix', publishPresenceOnCards);
    await p.setString('$_kAlias$suffix', displayAlias);
    await p.setString('$_kSecondary$suffix', secondaryPhone);
  }

  Future<void> _patchDb(Map<String, dynamic> patch) async {
    final uid = (_uid ?? '').trim();
    if (uid.isEmpty || !_dbColumnsAvailable) return;
    try {
      await Supabase.instance.client
          .from('users_profiles')
          .update(patch)
          .eq('user_id', uid);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('does not exist') || msg.contains('column')) {
        _dbColumnsAvailable = false;
        if (kDebugMode) {
          debugPrint('PublisherIdentityPrefs: DB columns missing — local only');
        }
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchProfile(String uid) async {
    final attempts = <String>[
      'account_type,office_name,phone,display_name,public_name_source,'
          'secondary_phone,public_phone_source,publish_presence_on_cards,'
          'first_name_ar,second_name_ar,third_name_ar,fourth_name_ar,'
          'first_name_en,second_name_en,third_name_en,fourth_name_en,'
          'full_name_ar,full_name_en,full_name',
      'account_type,office_name,phone,'
          'first_name_ar,second_name_ar,third_name_ar,fourth_name_ar,'
          'first_name_en,second_name_en,third_name_en,fourth_name_en,'
          'full_name_ar,full_name_en,full_name',
      'account_type,office_name,phone,full_name',
    ];
    for (final cols in attempts) {
      try {
        final row = await Supabase.instance.client
            .from('users_profiles')
            .select(cols)
            .eq('user_id', uid)
            .maybeSingle();
        if (row != null) {
          if (!cols.contains('display_name')) _dbColumnsAvailable = false;
          return Map<String, dynamic>.from(row);
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static PublicNameSource _parseNameSource(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'display':
        return PublicNameSource.display;
      default:
        return PublicNameSource.official;
    }
  }

  static PublicPhoneSource _parsePhoneSource(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'secondary':
        return PublicPhoneSource.secondary;
      case 'hidden':
        return PublicPhoneSource.hidden;
      default:
        return PublicPhoneSource.primary;
    }
  }

  /// هل الاسم الرسمي ناقص ويستحق الاستكمال (أجزاء أو مقابل إنجليزي)؟
  static bool officialNameNeedsCompletion(
    Map<String, dynamic>? row, {
    required bool isAr,
  }) {
    if (row == null) return true;
    String pick(String k) => (row[k] ?? '').toString().trim();
    final at = pick('account_type').toLowerCase();
    const org = {'office', 'institution', 'company', 'agency'};
    if (org.contains(at)) {
      return pick('office_name').isEmpty;
    }

    final arParts = [
      pick('first_name_ar'),
      pick('second_name_ar'),
      pick('third_name_ar'),
      pick('fourth_name_ar'),
    ].where((e) => e.isNotEmpty).toList();
    final enParts = [
      pick('first_name_en'),
      pick('second_name_en'),
      pick('third_name_en'),
      pick('fourth_name_en'),
    ].where((e) => e.isNotEmpty).toList();

    final arOk = arParts.length >= 2 ||
        CompoundDisplayName.normalize(pick('full_name_ar')).isNotEmpty;
    final enOk = enParts.length >= 2 ||
        CompoundDisplayName.normalize(pick('full_name_en')).isNotEmpty;

    // ناقص إن لم يوجد رباعي/ثنائي كافٍ، أو وُجد طرف واحد بلا مقابل.
    if (!arOk && !enOk) return true;
    if (arOk && !enOk) return true;
    if (enOk && !arOk) return true;
    return false;
  }
}
