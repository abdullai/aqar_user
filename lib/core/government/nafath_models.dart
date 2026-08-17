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
  });

  final NafathSessionMode mode;
  final String? authorizationUrl;
  final String? requestId;
  final String? random;
  final String? status;
  final String? messageAr;
  final String? messageEn;
  final String? rawError;

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
    );
  }
}
