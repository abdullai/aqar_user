import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/signature_blue_ink.dart';

enum FalComplianceLevel { ok, warnWeek, blockedExpired }

/// فحص رخصة فال / اكتمال الملف (مسوّق، مكتب، مؤسسة، شركة).
class ProfileComplianceService {
  /// توقيع مؤجّل من شاشة التسجيل عندما لا تُنشأ جلسة فورًا (تأكيد البريد).
  static const String kPrefPendingSignupSignatureB64 =
      'pending_signup_signature_b64';

  static const _falTypes = {'marketer', 'office', 'institution', 'company'};

  static Future<void> clearPendingSignupSignaturePref() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(kPrefPendingSignupSignatureB64);
    } catch (_) {}
  }

  /// بعد أول تسجيل دخول ناجح: رفع التوقيع المحفوظ أثناء التسجيل ثم حذف المفتاح.
  static Future<void> tryUploadPendingSignupSignature(SupabaseClient sb) async {
    if (sb.auth.currentUser == null) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final b64 = sp.getString(kPrefPendingSignupSignatureB64);
      if (b64 == null || b64.isEmpty) return;
      final bytes = base64Decode(b64);
      if (bytes.isEmpty) return;
      await uploadSignatureRasterBytes(sb, bytes);
      await sp.remove(kPrefPendingSignupSignatureB64);
    } catch (_) {}
  }

  static bool accountTypeNeedsFal(String? accountType) {
    return _falTypes.contains((accountType ?? '').trim().toLowerCase());
  }

  /// تحميل صف الامتثال — محاولة كاملة ثم أعمدة أقل عند فشل RLS/عمود ناقص
  /// حتى لا يُعاد `null` بالخطأ فيُتخطى التوقيع/فال/المراجعة.
  static Future<Map<String, dynamic>?> loadProfileRow(SupabaseClient sb) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return null;

    const fullCols = 'account_type, username, unified_national_number, '
        'fal_license_expires_at, fal_compliance_hold, '
        'signature_storage_path, verification_status, license_no, '
        'profile_data_revision';

    Future<Map<String, dynamic>?> oneSelect(String cols) async {
      final row = await sb
          .from('users_profiles')
          .select(cols)
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    }

    try {
      final m = await oneSelect(fullCols);
      if (m != null) {
        m.putIfAbsent('profile_data_revision', () => 1);
        return m;
      }
      return null;
    } catch (_) {
      try {
        final m = await oneSelect(
          'account_type, username, unified_national_number, '
          'fal_license_expires_at, fal_compliance_hold, '
          'signature_storage_path, verification_status, license_no, '
          'profile_data_revision',
        );
        if (m != null) {
          m.putIfAbsent('profile_data_revision', () => 1);
        }
        return m;
      } catch (_) {
        return null;
      }
    }
  }

  static FalComplianceLevel evaluateFal(Map<String, dynamic>? row) {
    if (row == null) return FalComplianceLevel.ok;
    if (!accountTypeNeedsFal(row['account_type']?.toString())) {
      return FalComplianceLevel.ok;
    }
    if (row['fal_compliance_hold'] == true) {
      return FalComplianceLevel.blockedExpired;
    }
    final expRaw = row['fal_license_expires_at'];
    if (expRaw == null) return FalComplianceLevel.ok;
    final d = DateTime.tryParse(expRaw.toString());
    if (d == null) return FalComplianceLevel.ok;
    final now = DateTime.now();
    if (!d.isAfter(now)) return FalComplianceLevel.blockedExpired;
    if (d.difference(now) <= const Duration(days: 7)) {
      return FalComplianceLevel.warnWeek;
    }
    return FalComplianceLevel.ok;
  }

  /// توقيع إلزامي إن كان المسار فارغاً — يشمل الحسابات القديمة بمجرد توفر صف الملف.
  static bool needsSignature(Map<String, dynamic>? row) {
    if (row == null) return false;
    final p = row['signature_storage_path']?.toString().trim() ?? '';
    final lower = p.toLowerCase();
    return p.isEmpty || lower.contains('placeholder');
  }

  /// بعد تجديد فال ناجح من الواجهة.
  static Future<void> applyFalRenewal({
    required SupabaseClient sb,
    required String licenseDigits,
    required Map<String, dynamic> regaSnapshot,
    DateTime? expiresAt,
  }) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw 'no_session';
    final patch = <String, dynamic>{
      'license_no': licenseDigits,
      'rega_fal_snapshot': regaSnapshot,
      'fal_compliance_hold': false,
    };
    if (expiresAt != null) {
      patch['fal_license_expires_at'] = expiresAt.toUtc().toIso8601String();
    }
    try {
      await sb.from('users_profiles').update(patch).eq('user_id', uid);
    } on PostgrestException catch (_) {
      patch.remove('fal_license_expires_at');
      patch.remove('rega_fal_snapshot');
      await sb.from('users_profiles').update({
        'license_no': licenseDigits,
        'fal_compliance_hold': false,
      }).eq('user_id', uid);
    }
  }

  static Future<void> setComplianceHold(SupabaseClient sb, bool hold) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await sb.from('users_profiles').update({
        'fal_compliance_hold': hold,
      }).eq('user_id', uid);
    } catch (_) {}
  }

  static Future<void> saveSignaturePath(SupabaseClient sb, String path) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw 'no_session';
    await sb.from('users_profiles').update({
      'signature_storage_path': path,
    }).eq('user_id', uid);
  }

  /// رفع توقيع (رسم أو ملف): يُطبَّق نمط «قلم أزرق» موحّد ثم يُخزَّن كـ PNG.
  static Future<void> uploadSignatureRasterBytes(
    SupabaseClient sb,
    Uint8List rawBytes,
  ) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw 'no_session';
    if (rawBytes.isEmpty) throw 'empty_signature';

    Uint8List? out = applySignatureBlueInkStyle(rawBytes);
    if (out == null) {
      final dec = img.decodeImage(rawBytes);
      if (dec == null) throw 'bad_image';
      final pngEnc = Uint8List.fromList(img.encodePng(dec));
      out = applySignatureBlueInkStyle(pngEnc) ?? pngEnc;
    }
    if (out.isEmpty) throw 'bad_image';

    final path =
        '$uid/signature/sig_${DateTime.now().millisecondsSinceEpoch}.png';

    await sb.storage.from('kyc').uploadBinary(
          path,
          out,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: false,
          ),
        );
    await saveSignaturePath(sb, path);
  }

  static Future<void> uploadSignaturePngBytes(
    SupabaseClient sb,
    Uint8List pngBytes,
  ) =>
      uploadSignatureRasterBytes(sb, pngBytes);
}
