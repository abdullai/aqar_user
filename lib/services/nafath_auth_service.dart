import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/government/nafath_models.dart';
import '../shared/core/supabase_config.dart';

/// مصادقة عبر **نفاذ** — يمرّ كل شيء عبر Edge Function على Supabase؛
/// لا تُخزَّن مفاتيح جهات حكومية داخل التطبيق.
///
/// عند تفعيل التكامل الحقيقي: تضبط أسراراً على الخادم فقط (`NAFATH_*`) وتُحدّث
/// [supabase/functions/nafath_session/index.ts] حسب عقدكم مع الجهة المعنية.
///
/// الاستخدام:
/// ```dart
/// final nafathService = NafathAuthService(supabaseClient);
/// final result = await nafathService.startLogin(nationalId: '1234567890');
/// if (result.mode == NafathSessionMode.polling) {
///   // عرض رقم التحقق للمستخدم
///   showDialog(..., random: result.random);
///   // ثم استعلم عن الحالة كل ثانية
///   await nafathService.pollStatus(result.requestId!);
/// }
/// ```
class NafathAuthService {
  NafathAuthService(this._sb);

  final SupabaseClient _sb;

  static const String functionName = 'nafath_session';
  static const Duration pollInterval = Duration(seconds: 2);
  static const int maxPollRetries = 30; // ~60 ثانية

  /// رأس الطلب الآمن — استخدم مفتاح Supabase الموجود
  Map<String, String>? _edgeHeaders() {
    final anon = SupabaseConfig.supabaseAnonKey.trim();
    if (anon.isEmpty) return null;
    // نفاذ يبدأ قبل وجود جلسة مستخدم، لذا Edge Function يجب أن يُنشَّر بدون verify_jwt.
    // لكننا نرسل Anon Key حتى يتمكّن Supabase من تحديد المشروع بشكل متسق.
    final session = _sb.auth.currentSession;
    final token = (session?.accessToken ?? '').trim();
    final bearer = token.isNotEmpty ? token : anon;
    return {
      'Authorization': 'Bearer $bearer',
      'apikey': anon,
    };
  }

  NafathSessionResult? _functionError(FunctionException error) {
    final details = error.details;
    if (details is Map && details['mode'] is String) {
      return NafathSessionResult.fromJson(Map<String, dynamic>.from(details));
    }
    return null;
  }

  /// يبدأ طلب دخول نفاذ (الخادم يعيد رابطاً أو حالة انتظار).
  ///
  /// [flow]: `login` للدخول، `register` لتحديد غرض طلب نفاذ. إنشاء الحساب
  /// وربطه بجلسة Supabase غير مفعّل حتى الآن.
  ///
  /// [locale]: لغة الرسائل (`ar` أو `en`)
  /// [nationalId]: رقم الهوية/الإقامة (10 أرقام)
  ///
  /// العائد:
  /// - [NafathSessionMode.polling]: اختبر المستخدم من هاتفه، استعلم عن الحالة بـ [pollStatus]
  /// - [NafathSessionMode.redirect]: تم التحقق، افتح الرابط
  /// - [NafathSessionMode.notConfigured]: الخادم لم يتم تفعيله بعد
  /// - [NafathSessionMode.error]: خطأ شبكة/بيانات
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
      return const NafathSessionResult(
        mode: NafathSessionMode.error,
        messageAr: 'استجابة غير متوقعة من الخادم.',
        messageEn: 'Unexpected server response.',
      );
    } on FunctionException catch (e) {
      return _functionError(e) ??
          NafathSessionResult(
            mode: NafathSessionMode.error,
            messageAr: 'تعذر الاتصال بخدمة نفاذ.',
            messageEn: 'Could not contact the Nafath service.',
            rawError: e.toString(),
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

  /// يبدأ عملية دخول عبر نفاذ.
  ///
  /// المعاملات:
  /// - [locale]: لغة الواجهة (`ar` أو `en`)
  /// - [nationalId]: رقم الهوية/الإقامة (10 أرقام)
  ///
  /// مثال:
  /// ```dart
  /// final result = await nafathService.startLogin(nationalId: '1234567890');
  /// ```
  Future<NafathSessionResult> startLogin({
    String locale = 'ar',
    required String nationalId,
  }) =>
      startSession(locale: locale, flow: 'login', nationalId: nationalId);

  /// يبدأ عملية تسجيل عبر نفاذ (لمستخدم جديد).
  ///
  /// المعاملات:
  /// - [locale]: لغة الواجهة (`ar` أو `en`)
  /// - [nationalId]: رقم الهوية/الإقامة (10 أرقام)
  ///
  /// مثال:
  /// ```dart
  /// final result = await nafathService.startRegistration(nationalId: '1234567890');
  /// ```
  Future<NafathSessionResult> startRegistration({
    String locale = 'ar',
    required String nationalId,
  }) =>
      startSession(locale: locale, flow: 'register', nationalId: nationalId);

  /// يستعلم عن حالة طلب نفاذ السابق.
  ///
  /// بعد استدعاء [startLogin] أو [startRegistration]، استخدم [pollStatus] مع
  /// [requestId] من النتيجة السابقة للتحقق مما إذا كان المستخدم وافق.
  ///
  /// المعاملات:
  /// - [requestId]: معرف الطلب (من نتيجة [startSession])
  ///
  /// مثال:
  /// ```dart
  /// while (true) {
  ///   final status = await nafathService.pollStatus(result.requestId!);
  ///   if (status.mode == NafathSessionMode.redirect) {
  ///     // تم التحقق — افتح الرابط
  ///     launchUrl(Uri.parse(status.authorizationUrl!));
  ///     break;
  ///   } else if (status.mode == NafathSessionMode.error) {
  ///     // خطأ — توقف
  ///     break;
  ///   }
  ///   await Future.delayed(Duration(seconds: 2));
  /// }
  /// ```
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
      return const NafathSessionResult(
        mode: NafathSessionMode.error,
        messageAr: 'استجابة غير متوقعة.',
        messageEn: 'Unexpected response.',
      );
    } on FunctionException catch (e) {
      return _functionError(e) ??
          NafathSessionResult(
            mode: NafathSessionMode.error,
            messageAr: 'تعذر استعلام حالة نفاذ.',
            messageEn: 'Could not query the Nafath status.',
            rawError: e.toString(),
          );
    } catch (e) {
      return NafathSessionResult(
        mode: NafathSessionMode.error,
        messageAr: 'خطأ في استعلام الحالة: $e',
        messageEn: 'Status poll error: $e',
        rawError: e.toString(),
      );
    }
  }

  /// يستعلم عن حالة الطلب بشكل متكرر حتى الانتهاء أو حدوث خطأ.
  ///
  /// هذه دالة مساعدة تقوم بالاستعلام تلقائياً كل [pollInterval] حتى:
  /// - يتم التحقق ([NafathSessionMode.redirect])
  /// - حدث خطأ ([NafathSessionMode.error] أو [NafathSessionMode.notConfigured])
  /// - تجاوز العدد الأقصى للمحاولات
  ///
  /// المعاملات:
  /// - [requestId]: معرف الطلب
  /// - [onProgress]: يُستدعى في كل استعلام (اختياري)
  ///
  /// مثال:
  /// ```dart
  /// final result = await nafathService.pollStatusUntilComplete(
  ///   result.requestId!,
  ///   onProgress: (r) => setState(() => random = r.random),
  /// );
  /// ```
  Future<NafathSessionResult> pollStatusUntilComplete(
    String requestId, {
    Function(NafathSessionResult)? onProgress,
  }) async {
    for (int i = 0; i < maxPollRetries; i++) {
      final result = await pollStatus(requestId);
      onProgress?.call(result);

      if (result.mode == NafathSessionMode.redirect ||
          result.mode == NafathSessionMode.error ||
          result.mode == NafathSessionMode.notConfigured) {
        return result;
      }

      if (i < maxPollRetries - 1) {
        await Future.delayed(pollInterval);
      }
    }

    return const NafathSessionResult(
      mode: NafathSessionMode.error,
      messageAr: 'انتهت المحاولات بدون رد من نفاذ.',
      messageEn: 'No response from Nafath after retries.',
    );
  }

  /// يستعلم عن بيانات المستخدم من نفاذ (بعد التحقق الناجح).
  ///
  /// هذه دالة مساعدة لاستخراج بيانات المستخدم من الاستجابة.
  /// يُستدعى هذا تلقائياً إذا كانت البيانات متوفرة في الاستجابة.
  ///
  /// المعاملات:
  /// - [result]: نتيجة [pollStatus] أو [pollStatusUntilComplete]
  ///
  /// مثال:
  /// ```dart
  /// final userData = nafathService.extractUserData(result);
  /// if (userData != null) {
  ///   // استخدم بيانات المستخدم
  ///   print(userData.fullName);
  /// }
  /// ```
  NafathUserData? extractUserData(NafathSessionResult result) {
    return result.userData;
  }

  /// Installs a real Supabase session returned by the trusted Nafath backend.
  Future<NafathSessionResult> completeAuthenticationFlow(
    NafathSessionResult result, {
    Function(String userId)? onUserCreated,
  }) async {
    if (result.mode != NafathSessionMode.redirect ||
        result.status != 'COMPLETED' ||
        (result.refreshToken ?? '').trim().isEmpty) {
      return const NafathSessionResult(
        mode: NafathSessionMode.error,
        messageAr: 'لم يكتمل تسجيل الدخول الآمن بعد.',
        messageEn: 'A valid authenticated session was not returned.',
      );
    }

    late String userId;
    try {
      await _sb.auth.setSession(result.refreshToken!);
      userId = _sb.auth.currentUser?.id ?? '';
      if (userId.isEmpty) {
        return const NafathSessionResult(
          mode: NafathSessionMode.error,
          messageAr: 'لم يُرجع Supabase مستخدمًا مسجّل الدخول.',
          messageEn: 'Supabase did not return an authenticated user.',
        );
      }
    } catch (e) {
      return NafathSessionResult(
        mode: NafathSessionMode.error,
        messageAr: 'خطأ في إنهاء عملية المصادقة: $e',
        messageEn: 'Authentication completion error: $e',
        rawError: e.toString(),
      );
    }
    onUserCreated?.call(userId);
    return result;
  }
}
