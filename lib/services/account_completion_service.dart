import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/input/input_normalizers.dart';
import '../core/profile/publisher_identity_prefs.dart';
import '../core/utils/compound_display_name.dart';
import '../core/utils/profile_greeting_from_row.dart';
import '../core/utils/users_profiles_safe_select.dart';
import 'profile_compliance_service.dart';

/// فحص الحقول الإلزامية بعد الدخول (بدون كسر الحسابات القديمة).
class AccountCompletionService {
  static const _marketingTypes = {
    'marketer',
    'office',
    'institution',
    'company',
    'agency',
  };

  static const _deferUntilKeyPrefix = 'profile_enrollment_defer_until_ms__';
  static const _openMyPageOnceKey = 'post_auth_open_my_page_once_v1';

  /// تأجيل «ذكرني لاحقاً» لجلسة التطبيق الحالية فقط — كل تسجيل دخول جديد يعيد البوابة.
  static bool _sessionEnrollmentDeferred = false;

  static String? get _uid {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// تأجيل بوابة استكمال الملف حتى نهاية الجلسة الحالية (أو حتى [clearEnrollmentDeferred]).
  static Future<void> markEnrollmentDeferred({
    Duration ttl = const Duration(hours: 36),
  }) async {
    _sessionEnrollmentDeferred = true;
    // نُزيل أي تأجيل قديم عبر SharedPreferences حتى لا يتجاوز جلسات الدخول.
    final uid = (_uid ?? '').trim();
    if (uid.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('$_deferUntilKeyPrefix$uid');
    } catch (_) {}
  }

  static Future<bool> isEnrollmentDeferred() async {
    return _sessionEnrollmentDeferred;
  }

  static Future<void> clearEnrollmentDeferred() async {
    _sessionEnrollmentDeferred = false;
    final uid = (_uid ?? '').trim();
    if (uid.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('$_deferUntilKeyPrefix$uid');
    } catch (_) {}
  }

  /// لا يُعرض «ذكرني لاحقاً» عند هوية/رخصة منتهية أو موقوفة — يجب الاستكمال فوراً.
  static bool allowRemindLater(Map<String, dynamic>? row) {
    if (row == null) return false;
    final fal = ProfileComplianceService.evaluateFal(row);
    if (fal == FalComplianceLevel.blockedExpired) return false;
    return true;
  }

  /// بعد «ذكرني لاحقاً» للمستخدم العائد: افتح صفحتي مرة واحدة.
  static Future<void> requestOpenMyPageOnce() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_openMyPageOnceKey, true);
    } catch (_) {}
  }

  static Future<bool> consumeOpenMyPageOnce() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getBool(_openMyPageOnceKey) == true;
      if (v) await p.remove(_openMyPageOnceKey);
      return v;
    } catch (_) {
      return false;
    }
  }

  static bool accountTypeNeedsUnifiedNational(String? accountType) {
    return _marketingTypes.contains((accountType ?? '').trim().toLowerCase());
  }

  static bool hasValidUnifiedNational(Map<String, dynamic>? row) {
    if (row == null) return false;
    final d = digitsOnly(
      normalizeAsciiDigits(
        (row['unified_national_number'] ?? '').toString(),
      ),
    );
    return isValidUnifiedNationalNumberDigits(d);
  }

  /// هل يجب إيقاف الدخول لاستكمال الرقم الوطني الموحّد فقط؟
  static bool needsUnifiedNationalCompletion(Map<String, dynamic>? row) {
    if (row == null) return false;
    final at = row['account_type']?.toString();
    if (!accountTypeNeedsUnifiedNational(at)) return false;
    return !hasValidUnifiedNational(row);
  }

  /// بيانات أساسية ناقصة بعد OTP (أوسع من التوقيع فقط): جوال، هوية مستخدمة كـ username، رخصة فال للمهنيين.
  /// لا يتضمّن التوقيع — يبقى [PostAuthShellStep.signatureRequired] كما هو.
  /// مصدر الحقيقة نفسه لـ [missingFieldLabels] (بدون تحذير أسبوع فال — لا يحجب الدخول).
  static bool needsMandatoryProfileEnrollment(Map<String, dynamic>? row) {
    if (row == null) return false;
    return missingFieldLabels(
      row,
      isAr: true,
      includeFalWeekWarning: false,
    ).isNotEmpty;
  }

  static bool needsIdentityUsername(Map<String, dynamic>? row) {
    if (row == null) return true;
    final idDigits = digitsOnly(
      normalizeAsciiDigits((row['username'] ?? '').toString()),
    );
    return idDigits.length != 10;
  }

  /// يحتاج حقل اسم عرض لأن المعرّف رقمي أو الاسم فارغ/مطابق للرقم.
  static bool needsDisplayNameCompletion(
    Map<String, dynamic>? row, {
    required bool isAr,
  }) {
    if (row == null) return false;
    final username = (row['username'] ?? '').toString().trim();
    if (!CompoundDisplayName.looksLikeNumericUsername(username)) {
      // حتى لو ليس رقمياً: إن لم يوجد أي اسم عرض في الملف
      final dn = ProfileGreetingFromRow.displayName(row, isAr: isAr)?.trim() ?? '';
      return dn.isEmpty;
    }
    final dn = ProfileGreetingFromRow.displayName(row, isAr: isAr)?.trim() ?? '';
    if (dn.isEmpty) return true;
    final dnDigits = digitsOnly(normalizeAsciiDigits(dn));
    final unDigits = digitsOnly(normalizeAsciiDigits(username));
    return dnDigits == unDigits || dn == username;
  }

  /// قائمة نواقص ظاهرة للمستخدم (إعدادات / بوابة استكمال).
  /// يفحص الجوال، الهوية، أسماء الظهور (عربي+إنجليزي عند كون المعرّف رقمياً)،
  /// الاسم الرسمي، الرقم الوطني الموحّد، ورخصة فال المنتهية/الناقصة.
  static List<String> missingFieldLabels(
    Map<String, dynamic>? row, {
    required bool isAr,
    bool includeFalWeekWarning = true,
  }) {
    if (row == null) {
      return [
        isAr ? 'ملف المستخدم غير متوفر' : 'Profile record missing',
      ];
    }
    final out = <String>[];
    final ph = digitsOnly(
      normalizeAsciiDigits((row['phone'] ?? '').toString()),
    );
    if (ph.length < 10) {
      out.add(isAr ? 'رقم الجوال' : 'Phone number');
    }
    if (needsIdentityUsername(row)) {
      out.add(
        isAr
            ? 'رقم الهوية (المعرّف) — 10 أرقام'
            : 'Identity ID (username) — 10 digits',
      );
    }
    // نفس شرط البوابة: ناقص إن كان أي من الاسمين (عربي/إنجليزي) فارغاً أو رقمياً.
    final needDnAr = needsDisplayNameCompletion(row, isAr: true);
    final needDnEn = needsDisplayNameCompletion(row, isAr: false);
    if (needDnAr || needDnEn) {
      out.add(isAr ? 'اسم الظهور المستعار' : 'Display alias');
    }
    if (PublisherIdentityPrefs.officialNameNeedsCompletion(row, isAr: isAr)) {
      out.add(
        isAr
            ? 'الاسم/الصفة المعتمدة (عربي + إنجليزي)'
            : 'Official registered name (AR + EN)',
      );
    }
    if (needsUnifiedNationalCompletion(row)) {
      out.add(isAr ? 'الرقم الوطني الموحّد' : 'Unified national number');
    }
    if (accountTypeNeedsUnifiedNational(row['account_type']?.toString())) {
      final lic = (row['license_no'] ?? '').toString().trim();
      if (lic.isEmpty) {
        out.add(isAr ? 'رخصة فال' : 'FAL license');
      }
      final fal = ProfileComplianceService.evaluateFal(row);
      if (fal == FalComplianceLevel.blockedExpired) {
        out.add(
          isAr ? 'رخصة فال منتهية أو موقوفة' : 'FAL license expired / on hold',
        );
      } else if (includeFalWeekWarning && fal == FalComplianceLevel.warnWeek) {
        out.add(
          isAr
              ? 'رخصة فال تنتهي خلال أسبوع'
              : 'FAL license expires within a week',
        );
      }
    }
    return out;
  }

  /// يحفظ معرّف الهوية (username) كـ 10 أرقام عند النقص فقط.
  static Future<void> saveIdentityUsername({
    required SupabaseClient sb,
    required String tenDigits,
  }) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw 'no_session';
    final d = digitsOnly(normalizeAsciiDigits(tenDigits));
    if (d.length != 10) throw 'invalid_identity';
    final existing = await sb
        .from('users_profiles')
        .select('username')
        .eq('user_id', uid)
        .maybeSingle();
    final cur = digitsOnly(
      normalizeAsciiDigits((existing?['username'] ?? '').toString()),
    );
    if (cur.length == 10 && cur != d) {
      throw 'identity_locked';
    }
    await sb.from('users_profiles').update({
      'username': d,
    }).eq('user_id', uid);
  }

  /// يحفظ رقم رخصة فال (بدون تحقق REGA — للتحقق استخدم [FalLicenseService]).
  static Future<void> saveLicenseNo({
    required SupabaseClient sb,
    required String licenseRaw,
  }) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw 'no_session';
    final d = digitsOnly(normalizeAsciiDigits(licenseRaw));
    if (d.length < 8) throw 'invalid_license';
    await sb.from('users_profiles').update({
      'license_no': d,
    }).eq('user_id', uid);
  }

  static Future<Map<String, dynamic>?> loadRow(SupabaseClient sb) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await UsersProfilesSafeSelect.fetchProfileById(
        sb,
        uid,
        columnAttempts: const [
          'user_id,account_type,unified_national_number,username,phone,license_no,'
              'fal_license_expires_at,fal_compliance_hold,'
              'display_name,public_name_source,secondary_phone,public_phone_source,'
              'publish_presence_on_cards,'
              'first_name_ar,second_name_ar,third_name_ar,fourth_name_ar,'
              'first_name_en,second_name_en,third_name_en,fourth_name_en,'
              'full_name_ar,full_name_en,full_name,office_name,status,created_at',
          'user_id,account_type,unified_national_number,username,phone,license_no,'
              'fal_license_expires_at,fal_compliance_hold,'
              'first_name_ar,second_name_ar,third_name_ar,fourth_name_ar,'
              'first_name_en,second_name_en,third_name_en,fourth_name_en,'
              'full_name_ar,full_name_en,full_name,office_name,status,created_at',
          'user_id,account_type,unified_national_number,username,phone,license_no,'
              'fal_license_expires_at,fal_compliance_hold',
          'user_id,account_type,unified_national_number,username,phone,license_no',
          'user_id,account_type,unified_national_number,username',
          'user_id,account_type,username',
          'user_id,username',
          'user_id',
        ],
      );
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveUnifiedNational({
    required SupabaseClient sb,
    required String tenDigits700,
  }) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw 'no_session';
    final d = digitsOnly(normalizeAsciiDigits(tenDigits700));
    if (!isValidUnifiedNationalNumberDigits(d)) {
      throw 'invalid_unified_national';
    }
    await sb.from('users_profiles').update({
      'unified_national_number': d,
    }).eq('user_id', uid);
  }

  /// يحفظ اسم الظهور المستعار فقط — لا يمس الاسم/الصفة المعتمدة للمعاملات الرسمية.
  static Future<void> saveDisplayName({
    required SupabaseClient sb,
    required String displayName,
    required bool isAr,
  }) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw 'no_session';
    final normalized = CompoundDisplayName.normalize(displayName);
    if (normalized.isEmpty) throw 'invalid_name';

    // المستعار في display_name (+ احتياطي full_name للتوافق مع الشاشات القديمة).
    try {
      await sb.from('users_profiles').update({
        'display_name': normalized,
        'full_name': normalized,
        if (isAr) 'full_name_ar': normalized else 'full_name_en': normalized,
      }).eq('user_id', uid);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('display_name') && msg.contains('does not exist')) {
        await sb.from('users_profiles').update({
          'full_name': normalized,
          if (isAr) 'full_name_ar': normalized else 'full_name_en': normalized,
        }).eq('user_id', uid);
      } else {
        rethrow;
      }
    }
  }

  /// يحفظ الاسم الرباعي الرسمي (عربي + إنجليزي) عند الاستكمال فقط.
  static Future<void> saveOfficialQuadNames({
    required SupabaseClient sb,
    required List<String> arParts,
    required List<String> enParts,
  }) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw 'no_session';
    final ar = arParts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final en = enParts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (ar.length < 2 && en.length < 2) throw 'invalid_name';
    final arFull = CompoundDisplayName.normalize(ar.join(' '));
    final enFull = CompoundDisplayName.normalize(en.join(' '));
    final payload = <String, dynamic>{
      if (arFull.isNotEmpty) ...{
        'full_name_ar': arFull,
        'full_name': arFull,
        'first_name_ar': ar.isNotEmpty ? ar[0] : '',
        'second_name_ar': ar.length > 1 ? ar[1] : '',
        'third_name_ar': ar.length > 2 ? ar[2] : '',
        'fourth_name_ar': ar.length > 3 ? ar.sublist(3).join(' ') : '',
      },
      if (enFull.isNotEmpty) ...{
        'full_name_en': enFull,
        'first_name_en': en.isNotEmpty ? en[0] : '',
        'second_name_en': en.length > 1 ? en[1] : '',
        'third_name_en': en.length > 2 ? en[2] : '',
        'fourth_name_en': en.length > 3 ? en.sublist(3).join(' ') : '',
      },
    };
    await sb.from('users_profiles').update(payload).eq('user_id', uid);
  }

  /// يحفظ الجوال الأساسي فقط إن كان فارغاً — لا يُستبدل رقم مسجّل.
  static Future<void> savePhone({
    required SupabaseClient sb,
    required String phoneRaw,
  }) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw 'no_session';
    var d = digitsOnly(normalizeAsciiDigits(phoneRaw));
    if (d.startsWith('966') && d.length >= 12) {
      d = '0${d.substring(3)}';
    } else if (d.startsWith('5') && d.length == 9) {
      d = '0$d';
    }
    if (d.startsWith('05')) {
      if (d.length != 10) throw 'invalid_phone';
    } else if (d.length < 10 || d.length > 15) {
      throw 'invalid_phone';
    }

    final existing = await sb
        .from('users_profiles')
        .select('phone')
        .eq('user_id', uid)
        .maybeSingle();
    final cur = digitsOnly(
      normalizeAsciiDigits((existing?['phone'] ?? '').toString()),
    );
    if (cur.length >= 10 && cur != d) {
      throw 'primary_phone_locked';
    }
    await sb.from('users_profiles').update({
      'phone': d,
    }).eq('user_id', uid);
  }
}
