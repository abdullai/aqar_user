import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/government/nafath_models.dart';
import '../shared/core/supabase_config.dart';

/// مصادقة عبر **نفاذ** — يمرّ كل شيء عبر Edge Function على Supabase؛
/// لا تُخزَّن مفاتيح جهات حكومية داخل التطبيق.
///
/// عند تفعيل التكامل الحقيقي: تضبط أسراراً على الخادم فقط (`NAFATH_*`) وتُحدّث
/// [supabase/functions/nafath_session/index.ts] حسب عقدكم مع الجهة المعنية.
class NafathAuthService {
  NafathAuthService(this._sb);

  final SupabaseClient _sb;

  static const String functionName = 'nafath_session';

  /// يبدأ طلب دخول نفاذ (الخادم يعيد رابطاً أو حالة انتظار).
  ///
  /// [flow]: `login` للدخول، `register` لإكمال تسجيل مستخدم جديد بعد المصادقة
  /// (يُنفَّذ على الخادم: إنشاء/ربط حساب Supabase ثم إرجاع جلسة أو رمز).
  Map<String, String>? _edgeHeaders() {
    final anon = SupabaseConfig.supabaseAnonKey.trim();
    if (anon.isEmpty) return null;
    // Nafath starts before a user session exists, so the Edge Function must be
    // deployed with verify_jwt=false. We still send the publishable/anon key so
    // the Supabase gateway can identify the project consistently.
    final session = _sb.auth.currentSession;
    final token = (session?.accessToken ?? '').trim();
    final bearer = token.isNotEmpty ? token : anon;
    return {
      'Authorization': 'Bearer $bearer',
      'apikey': anon,
    };
  }

  Future<NafathSessionResult> startSession({
    String locale = 'ar',
    String flow = 'login',
    required String nationalId,
  }) async {
    try {
      final res = await _sb.functions.invoke(
        functionName,
        body: {
          'action': 'start',
          'locale': locale,
          'flow': flow,
          'national_id': nationalId,
        },
        headers: _edgeHeaders(),
      );
      final data = res.data;
      if (data is Map) {
        return NafathSessionResult.fromJson(Map<String, dynamic>.from(data));
      }
      return NafathSessionResult(
        mode: NafathSessionMode.error,
        messageAr: 'استجابة غير متوقعة من الخادم.',
        messageEn: 'Unexpected server response.',
      );
    } catch (e) {
      return NafathSessionResult(
        mode: NafathSessionMode.error,
        messageAr: 'تعذر الاتصال بالخادم: $e',
        messageEn: 'Server error: $e',
        rawError: e.toString(),
      );
    }
  }

  Future<NafathSessionResult> startLogin({
    String locale = 'ar',
    required String nationalId,
  }) =>
      startSession(locale: locale, flow: 'login', nationalId: nationalId);

  Future<NafathSessionResult> startRegistration({
    String locale = 'ar',
    required String nationalId,
  }) =>
      startSession(locale: locale, flow: 'register', nationalId: nationalId);

  /// لاحقاً: استعلام حالة الطلب بعد إرجاع المستخدم من نفاذ.
  Future<NafathSessionResult> pollStatus(String requestId) async {
    try {
      final res = await _sb.functions.invoke(
        functionName,
        body: {
          'action': 'poll',
          'request_id': requestId,
        },
        headers: _edgeHeaders(),
      );
      final data = res.data;
      if (data is Map) {
        return NafathSessionResult.fromJson(Map<String, dynamic>.from(data));
      }
      return NafathSessionResult(
        mode: NafathSessionMode.error,
        messageAr: 'استجابة غير متوقعة.',
        messageEn: 'Unexpected response.',
      );
    } catch (e) {
      return NafathSessionResult(
        mode: NafathSessionMode.error,
        rawError: e.toString(),
      );
    }
  }
}
