/// نتيجة طلب جلسة نفاذ — تُستخرج من Edge Function [nafath_session].
/// يتطابق مع معايير API نفاذ الرسمية (NSI001/NSI002/NSI003).
enum NafathSessionMode {
  /// الخادم لم يُفعَّل بعد (لا أسرار في التطبيق).
  notConfigured,

  /// فتح رابط مصادقة (مستخدِم يُكمل في تطبيق نفاذ/المتصفح).
  redirect,

  /// انتظار اكتمال العملية عبر [requestId] (استعلام لاحق) — حالة NSI003: WAITING.
  polling,

  /// خطأ شبكة/استجابة.
  error,
}

/// حالات الطلب المتوقعة من API نفاذ (NSI003 - Retrieve Status).
enum NafathRequestStatus {
  waiting, // المستخدم لم يؤكد بعد
  completed, // تم التأكيد بنجاح
  rejected, // رفض الطلب
  expired, // انتهت مهلة الطلب
}

extension NafathStatusParsing on String {
  NafathRequestStatus? toNafathStatus() {
    switch (trim().toUpperCase()) {
      case 'WAITING':
        return NafathRequestStatus.waiting;
      case 'COMPLETED':
        return NafathRequestStatus.completed;
      case 'REJECTED':
        return NafathRequestStatus.rejected;
      case 'EXPIRED':
        return NafathRequestStatus.expired;
      default:
        return null;
    }
  }
}

/// بيانات المستخدم المجلوبة من نفاذ (اختياري — تُستخدَم عند تحديث الملف).
class NafathUserData {
  const NafathUserData({
    this.fullName,
    this.nationalId,
    this.gender,
    this.birthDate,
    this.nationality,
    this.occupation,
    this.addresses,
  });

  final String? fullName;
  final String? nationalId;
  final String? gender; // 'M', 'F'
  final String? birthDate; // YYYY-MM-DD
  final String? nationality;
  final String? occupation;
  final List<String>? addresses; // قائمة العناوين

  Map<String, dynamic> toJson() => {
        if (fullName != null) 'full_name': fullName,
        if (nationalId != null) 'national_id': nationalId,
        if (gender != null) 'gender': gender,
        if (birthDate != null) 'birth_date': birthDate,
        if (nationality != null) 'nationality': nationality,
        if (occupation != null) 'occupation': occupation,
        if (addresses != null) 'addresses': addresses,
      };

  static NafathUserData? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    return NafathUserData(
      fullName: j['full_name']?.toString(),
      nationalId: j['national_id']?.toString(),
      gender: j['gender']?.toString(),
      birthDate: j['birth_date']?.toString(),
      nationality: j['nationality']?.toString(),
      occupation: j['occupation']?.toString(),
      addresses: List<String>.from(j['addresses'] ?? []),
    );
  }
}

class NafathSessionResult {
  const NafathSessionResult({
    required this.mode,
    this.authorizationUrl,
    this.requestId,
    this.transId, // NSI002/NSI003: معرف المعاملة من نفاذ
    this.random,
    this.status,
    this.messageAr,
    this.messageEn,
    this.rawError,
    this.accessToken,
    this.refreshToken,
    this.userData,
    this.expiresAt, // انتهاء صلاحية الطلب
    this.errorCode, // رمز الخطأ من نفاذ (مثل 400-034-050)
  });

  final NafathSessionMode mode;
  final String? authorizationUrl;
  final String? requestId; // معرّف الطلب الداخلي (UUID)
  final String? transId; // معرّف المعاملة من نفاذ (NSI002/NSI003)
  final String? random; // الرقم العشوائي للعرض
  final String? status; // WAITING, COMPLETED, REJECTED, EXPIRED
  final String? messageAr;
  final String? messageEn;
  final String? rawError;
  final String? accessToken;
  final String? refreshToken;
  final NafathUserData? userData;
  final DateTime? expiresAt; // انتهاء صلاحية الطلب
  final String? errorCode; // مثل: 400-034-050

  static NafathSessionResult fromJson(Map<String, dynamic> j) {
    final modeStr = (j['mode'] ?? '').toString().trim();
    NafathSessionMode mode;
    switch (modeStr) {
      case 'redirect':
        mode = NafathSessionMode.redirect;
        break;
      case 'polling':
        mode = NafathSessionMode.polling;
        break;
      case 'not_configured':
        mode = NafathSessionMode.notConfigured;
        break;
      case 'error':
        mode = NafathSessionMode.error;
        break;
      default:
        mode = NafathSessionMode.error;
    }

    DateTime? expiresAt;
    final expiresStr = (j['expires_at'] ?? j['expiresAt'])?.toString().trim();
    if (expiresStr != null && expiresStr.isNotEmpty) {
      try {
        expiresAt = DateTime.parse(expiresStr);
      } catch (_) {}
    }

    return NafathSessionResult(
      mode: mode,
      authorizationUrl: j['authorization_url']?.toString(),
      requestId: j['request_id']?.toString(),
      transId: j['trans_id']?.toString(),
      random: j['random']?.toString(),
      status: j['status']?.toString(),
      messageAr: j['message_ar']?.toString(),
      messageEn: j['message_en']?.toString(),
      rawError: j['error']?.toString(),
      accessToken: (j['access_token'] ?? j['accessToken'])?.toString(),
      refreshToken: (j['refresh_token'] ?? j['refreshToken'])?.toString(),
      expiresAt: expiresAt,
      errorCode: j['error_code']?.toString(),
      userData: NafathUserData.fromJson(j['user_data'] is Map
          ? Map<String, dynamic>.from(j['user_data'] as Map)
          : null),
    );
  }
}
