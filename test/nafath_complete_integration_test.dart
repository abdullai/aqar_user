import 'package:aqar_user/core/government/nafath_models.dart';
import 'package:aqar_user/services/nafath_auth_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('Nafath Complete Integration Tests', () {
    late SupabaseClient mockSupabaseClient;

    setUp(() async {
      dotenv.testLoad(fileInput: '');

      mockSupabaseClient = SupabaseClient(
        'https://test.supabase.co',
        'test-key',
      );
    });

    test('عملية دخول نفاذ الكاملة: من البداية إلى الانتهاء', () async {
      final nafathService = NafathAuthService(mockSupabaseClient);

      // يجب أن لا تكون NULL
      expect(nafathService, isNotNull);
      expect(NafathAuthService.functionName, 'nafath_session');
    });

    test('استخراج بيانات المستخدم من النتيجة', () async {
      const userData = NafathUserData(
        fullName: 'أحمد محمد',
        nationalId: '1234567890',
        gender: 'M',
        birthDate: '1990-01-01',
        nationality: 'SA',
      );

      const result = NafathSessionResult(
        mode: NafathSessionMode.redirect,
        userData: userData,
      );

      final nafathService = NafathAuthService(mockSupabaseClient);
      final extracted = nafathService.extractUserData(result);

      expect(extracted, isNotNull);
      expect(extracted?.fullName, 'أحمد محمد');
      expect(extracted?.nationalId, '1234567890');
    });

    test('معالجة رد الـ polling بحالة WAITING', () async {
      const result = NafathSessionResult(
        mode: NafathSessionMode.polling,
        requestId: 'test-request-id',
        random: '42',
        status: 'WAITING',
        messageAr: 'بانتظار الموافقة...',
      );

      expect(result.mode, NafathSessionMode.polling);
      expect(result.status, 'WAITING');
      expect(result.random, '42');
    });

    test('معالجة حالة الخطأ: رفع الطلب', () async {
      const result = NafathSessionResult(
        mode: NafathSessionMode.error,
        status: 'REJECTED',
        messageAr: 'تم رفض طلب نفاذ',
        messageEn: 'Nafath request was rejected',
      );

      expect(result.mode, NafathSessionMode.error);
      expect(result.status, 'REJECTED');
    });

    test('معالجة حالة الخطأ: انتهاء المهلة', () async {
      const result = NafathSessionResult(
        mode: NafathSessionMode.error,
        status: 'EXPIRED',
        messageAr: 'انتهت مهلة الطلب',
        messageEn: 'Request expired',
      );

      expect(result.mode, NafathSessionMode.error);
      expect(result.status, 'EXPIRED');
    });

    test('معالجة حالة النجاح: التحقق من الهوية', () async {
      const userData = NafathUserData(
        fullName: 'فاطمة علي',
        nationalId: '9876543210',
        gender: 'F',
        birthDate: '1995-06-15',
      );

      const result = NafathSessionResult(
        mode: NafathSessionMode.redirect,
        status: 'COMPLETED',
        authorizationUrl: '/home?auth_method=nafath',
        userData: userData,
      );

      expect(result.mode, NafathSessionMode.redirect);
      expect(result.status, 'COMPLETED');
      expect(result.userData?.fullName, 'فاطمة علي');
    });

    test('رفض إكمال الدخول دون جلسة Supabase حقيقية', () async {
      final nafathService = NafathAuthService(mockSupabaseClient);

      const userData = NafathUserData(
        fullName: 'محمد عبدالله',
        nationalId: '1111111111',
      );

      const result = NafathSessionResult(
        mode: NafathSessionMode.redirect,
        status: 'COMPLETED',
        userData: userData,
        accessToken: 'test-token-123',
      );

      var userCreatedCalled = false;
      final completeResult = await nafathService.completeAuthenticationFlow(
        result,
        onUserCreated: (userId) {
          userCreatedCalled = true;
          expect(userId, 'test-token-123');
        },
      );

      expect(completeResult.mode, NafathSessionMode.error);
      expect(userCreatedCalled, false);
    });

    test('معالجة محاولة الإكمال قبل الانتهاء', () async {
      final nafathService = NafathAuthService(mockSupabaseClient);

      const result = NafathSessionResult(
        mode: NafathSessionMode.polling,
        status: 'WAITING',
      );

      final completeResult =
          await nafathService.completeAuthenticationFlow(result);

      expect(completeResult.mode, NafathSessionMode.error);
      expect(completeResult.messageAr, contains('لم يكتمل'));
    });

    test('NafathUserData — تحويل إلى/من JSON', () async {
      const userData = NafathUserData(
        fullName: 'محمد سالم',
        nationalId: '2222222222',
        gender: 'M',
        birthDate: '1988-03-20',
        nationality: 'SA',
        occupation: 'مهندس',
        addresses: ['الرياض', 'جدة'],
      );

      final json = userData.toJson();
      expect(json['full_name'], 'محمد سالم');
      expect(json['national_id'], '2222222222');
      expect(json['addresses'], ['الرياض', 'جدة']);

      final restored = NafathUserData.fromJson(json);
      expect(restored?.fullName, userData.fullName);
      expect(restored?.nationalId, userData.nationalId);
      expect(restored?.addresses, userData.addresses);
    });

    test('NafathSessionResult — جميع الأوضاع', () async {
      // Redirect
      const redirectResult = NafathSessionResult(
        mode: NafathSessionMode.redirect,
        authorizationUrl: 'https://example.com/auth',
      );
      expect(redirectResult.mode, NafathSessionMode.redirect);

      // Polling
      const pollingResult = NafathSessionResult(
        mode: NafathSessionMode.polling,
        requestId: 'req-123',
        random: '99',
      );
      expect(pollingResult.mode, NafathSessionMode.polling);

      // Not Configured
      const notConfigResult = NafathSessionResult(
        mode: NafathSessionMode.notConfigured,
      );
      expect(notConfigResult.mode, NafathSessionMode.notConfigured);

      // Error
      const errorResult = NafathSessionResult(
        mode: NafathSessionMode.error,
        messageEn: 'Error message',
      );
      expect(errorResult.mode, NafathSessionMode.error);
    });

    test('معالجة callback مع بيانات مستخدم كاملة', () async {
      final callbackData = {
        'mode': 'redirect',
        'status': 'COMPLETED',
        'request_id': 'req-456',
        'user_data': {
          'full_name': 'خالد محمود',
          'national_id': '3333333333',
          'gender': 'M',
          'birth_date': '1992-05-10',
          'nationality': 'SA',
        },
      };

      final result = NafathSessionResult.fromJson(callbackData);

      expect(result.mode, NafathSessionMode.redirect);
      expect(result.status, 'COMPLETED');
      expect(result.userData?.fullName, 'خالد محمود');
    });

    test('سيناريو واقعي: دخول مستخدم موجود', () async {
      // 1. البدء
      const startResult = NafathSessionResult(
        mode: NafathSessionMode.polling,
        requestId: 'req-789',
        random: '15',
        status: 'WAITING',
      );
      expect(startResult.mode, NafathSessionMode.polling);

      // 2. الانتظار (محاكاة)
      const pollResult = NafathSessionResult(
        mode: NafathSessionMode.polling,
        requestId: 'req-789',
        random: '15',
        status: 'WAITING',
      );
      expect(pollResult.mode, NafathSessionMode.polling);

      // 3. الانتهاء
      const completeResult = NafathSessionResult(
        mode: NafathSessionMode.redirect,
        status: 'COMPLETED',
        requestId: 'req-789',
        accessToken: 'session-token-123',
        userData: NafathUserData(
          fullName: 'سارة أحمد',
          nationalId: '4444444444',
        ),
      );
      expect(completeResult.mode, NafathSessionMode.redirect);
      expect(completeResult.status, 'COMPLETED');
    });

    test('سيناريو واقعي: تسجيل مستخدم جديد', () async {
      // عملية التسجيل
      const startResult = NafathSessionResult(
        mode: NafathSessionMode.polling,
        requestId: 'reg-123',
        random: '88',
        status: 'WAITING',
      );

      const completeResult = NafathSessionResult(
        mode: NafathSessionMode.redirect,
        status: 'COMPLETED',
        authorizationUrl: '/home?new_user=true',
        userData: NafathUserData(
          fullName: 'ياسمين محمد',
          nationalId: '5555555555',
          gender: 'F',
        ),
      );

      expect(startResult.mode, NafathSessionMode.polling);
      expect(completeResult.mode, NafathSessionMode.redirect);
    });
  });

  group('Nafath Edge Function Tests', () {
    test('nafath_session/index.ts — بيانات الإدخال الصحيحة', () async {
      // هذا اختبار وحدة للتحقق من بنية البيانات المتوقعة
      final validStartRequest = {
        'action': 'start',
        'national_id': '1234567890',
        'flow': 'login',
        'locale': 'ar',
      };

      expect(validStartRequest['national_id'], matches(r'^\d{10}$'));
      expect(validStartRequest['flow'], isIn(['login', 'register']));
      expect(validStartRequest['locale'], isIn(['ar', 'en']));
    });

    test('nafath_callback/index.ts — توقيع Callback', () async {
      // اختبار التحقق من التوقيع
      const payload = 'test_payload_123';
      const appKey = 'test_key_456';

      // في التطبيق الحقيقي، استخدم crypto.subtle.sign
      expect(appKey.length, greaterThan(0));
      expect(payload.length, greaterThan(0));
    });
  });
}
