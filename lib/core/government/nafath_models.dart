/// نتيجة طلب جلسة نفاذ — تُستخرج من Edge Function [nafath_session].
enum NafathSessionMode {
  /// الخادم لم يُفعَّل بعد (لا أسرار في التطبيق).
  notConfigured,

  /// فتح رابط مصادقة (مستخدِم يُكمل في تطبيق نفاذ/المتصفح).
  redirect,

  /// انتظار اكتمال العملية عبر [requestId] (استعلام لاحق).
  polling,

  /// خطأ شبكة/استجابة.
  error,
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
    this.random,
    this.status,
    this.messageAr,
    this.messageEn,
    this.rawError,
    this.accessToken,
    this.refreshToken,
    this.userData,
  });

  final NafathSessionMode mode;
  final String? authorizationUrl;
  final String? requestId;
  final String? random;
  final String? status;
  final String? messageAr;
  final String? messageEn;
  final String? rawError;
  final String? accessToken;
  final String? refreshToken;
  final NafathUserData? userData;

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
    return NafathSessionResult(
      mode: mode,
      authorizationUrl: j['authorization_url']?.toString(),
      requestId: j['request_id']?.toString(),
      random: j['random']?.toString(),
      status: j['status']?.toString(),
      messageAr: j['message_ar']?.toString(),
      messageEn: j['message_en']?.toString(),
      rawError: j['error']?.toString(),
      accessToken: (j['access_token'] ?? j['accessToken'])?.toString(),
      refreshToken: (j['refresh_token'] ?? j['refreshToken'])?.toString(),
      userData: NafathUserData.fromJson(
        j['user_data'] is Map ? Map<String, dynamic>.from(j['user_data'] as Map) : null
      ),
    );
  }
}
