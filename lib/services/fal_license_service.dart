import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fal_license_verify_result.dart';

/// استدعاء Edge Function [verify_fal_license] للتحقق من رخصة فال/الإعلان.
/// التكامل الكامل مع واجهات الهيئة العامة للعقار يتطلب مفاتيح وعقوداً على الخادم
/// (الدالة تبقى نقطة التوسعة؛ لا تُرسل أسرار من التطبيق).
class FalLicenseService {
  FalLicenseService(this._sb);

  final SupabaseClient _sb;

  Future<FalLicenseVerifyResult> verify(String rawLicenseNo) async {
    final licenseNo = rawLicenseNo.replaceAll(RegExp(r'\D'), '');
    if (licenseNo.length != 10) {
      return FalLicenseVerifyResult(
        valid: false,
        status: 'invalid_license_no',
        errorMessage: 'رقم الرخصة يجب أن يكون 10 أرقام.',
      );
    }

    try {
      final res = await _sb.functions.invoke(
        'verify_fal_license',
        body: {'license_no': licenseNo},
      );
      if (res.data is Map) {
        return FalLicenseVerifyResult.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
      }
      return FalLicenseVerifyResult(
        valid: false,
        status: 'bad_response',
        errorMessage: 'استجابة غير متوقعة من الخادم.',
      );
    } catch (e) {
      return FalLicenseVerifyResult(
        valid: false,
        status: 'network_error',
        errorMessage: e.toString(),
      );
    }
  }
}
