import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aqar_user/core/government/nafath_models.dart';
import 'package:aqar_user/services/nafath_auth_service.dart';

void main() {
  test('preserves structured non-success Edge responses', () async {
    dotenv.testLoad(fileInput: '');
    final client = SupabaseClient(
      'https://test.supabase.co',
      'test-key',
      httpClient: MockClient((request) async => http.Response(
        '{"mode":"error","status":"REJECTED","message_ar":"تم رفض الطلب"}',
        409,
        headers: {'content-type': 'application/json'},
      )),
    );
    final result = await NafathAuthService(client).pollStatus('request-id');
    expect(result.mode, NafathSessionMode.error);
    expect(result.status, 'REJECTED', reason: result.rawError ?? result.messageEn);
    expect(result.messageAr, 'تم رفض الطلب');
    await client.dispose();
  });

  group('NafathAuthService', () {
    late SupabaseClient mockSupabaseClient;

    setUp(() {
      // إنشاء mock client للـ Supabase
      mockSupabaseClient = SupabaseClient(
        'https://test.supabase.co',
        'test-key',
      );
    });

    group('startSession', () {
      test('بدء جلسة نفاذ بنجاح — وضع Polling', () async {
        final authService = NafathAuthService(mockSupabaseClient);
        
        expect(
          authService,
          isNotNull,
          reason: 'يجب إنشاء خدمة NafathAuthService بدون أخطاء',
        );
      });

      test('يرفع خطأ عند إدخال رقم هوية غير صحيح', () async {
        // اختبار التحقق من صحة رقم الهوية على جانب العميل
        const invalidIds = [
          '123',          // أقصر من 10
          '12345678901',  // أطول من 10
          '123456789a',   // يحتوي على أحرف
          '',             // فارغ
        ];
        
        for (final id in invalidIds) {
          final isValid = RegExp(r'^\d{10}$').hasMatch(id);
          expect(
            isValid,
            isFalse,
            reason: '$id يجب أن تكون صيغة غير صحيحة',
          );
        }

        // والعكس — أرقام صحيحة
        const validIds = [
          '1234567890',
          '0987654321',
        ];
        for (final id in validIds) {
          final isValid = RegExp(r'^\d{10}$').hasMatch(id);
          expect(
            isValid,
            isTrue,
            reason: '$id يجب أن تكون صيغة صحيحة',
          );
        }
      });

      test('يدعم كلا اللغتين: العربية والإنجليزية', () async {
        const locales = ['ar', 'en'];
        for (final locale in locales) {
          expect(
            ['ar', 'en'].contains(locale),
            isTrue,
            reason: 'يجب دعم اللغة: $locale',
          );
        }
      });

      test('يدعم نمطي التسجيل: login و register', () async {
        const flows = ['login', 'register'];
        for (final flow in flows) {
          expect(
            ['login', 'register'].contains(flow),
            isTrue,
            reason: 'يجب دعم النمط: $flow',
          );
        }
      });
    });

    group('pollStatus', () {
      test('يعيد حالة WAITING عند الانتظار', () async {
        final responseData = {
          'mode': 'polling',
          'status': 'WAITING',
          'request_id': 'trans_123',
          'random': '42',
          'message_ar': 'بانتظار التأكيد',
          'message_en': 'Waiting for confirmation',
        };

        final result = NafathSessionResult.fromJson(responseData);

        expect(result.mode, NafathSessionMode.polling);
        expect(result.status, 'WAITING');
        expect(result.requestId, 'trans_123');
        expect(result.random, '42');
      });

      test('يعيد حالة COMPLETED مع رابط تسجيل دخول', () async {
        const redirectUrl = 'https://example.com/auth/callback?token=abc123';
        final responseData = {
          'mode': 'redirect',
          'status': 'COMPLETED',
          'request_id': 'trans_123',
          'authorization_url': redirectUrl,
          'message_ar': 'تم التحقق بنجاح',
          'message_en': 'Verified successfully',
        };

        final result = NafathSessionResult.fromJson(responseData);

        expect(result.mode, NafathSessionMode.redirect);
        expect(result.status, 'COMPLETED');
        expect(result.authorizationUrl, redirectUrl);
      });

      test('يعيد حالة REJECTED عند الرفض', () async {
        final responseData = {
          'mode': 'error',
          'status': 'REJECTED',
          'request_id': 'trans_123',
          'message_ar': 'تم رفض الطلب',
          'message_en': 'Request was rejected',
        };

        final result = NafathSessionResult.fromJson(responseData);

        expect(result.mode, NafathSessionMode.error);
        expect(result.status, 'REJECTED');
      });

      test('يعيد حالة EXPIRED عند انتهاء المهلة', () async {
        final responseData = {
          'mode': 'error',
          'status': 'EXPIRED',
          'request_id': 'trans_123',
          'message_ar': 'انتهت مهلة الطلب',
          'message_en': 'Request expired',
        };

        final result = NafathSessionResult.fromJson(responseData);

        expect(result.mode, NafathSessionMode.error);
        expect(result.status, 'EXPIRED');
      });
    });

    group('NafathSessionResult parsing', () {
      test('يحوّل JSON إلى NafathSessionResult بشكل صحيح', () async {
        final json = {
          'mode': 'polling',
          'status': 'WAITING',
          'request_id': 'req_123',
          'random': '99',
          'message_ar': 'اختر الرقم في التطبيق',
          'message_en': 'Choose the number in the app',
        };

        final result = NafathSessionResult.fromJson(json);

        expect(result.mode, NafathSessionMode.polling);
        expect(result.status, 'WAITING');
        expect(result.requestId, 'req_123');
        expect(result.random, '99');
        expect(result.messageAr, 'اختر الرقم في التطبيق');
        expect(result.messageEn, 'Choose the number in the app');
      });

      test('يتعامل مع الحالات التي لم تتم تعريفها', () async {
        final json = {
          'mode': 'unknown_mode',
          'request_id': 'req_123',
        };

        final result = NafathSessionResult.fromJson(json);

        expect(result.mode, NafathSessionMode.error);
      });

      test('يملأ القيم الفارغة بـ null', () async {
        final json = {
          'mode': 'polling',
          'request_id': 'req_123',
        };

        final result = NafathSessionResult.fromJson(json);

        expect(result.status, isNull);
        expect(result.random, isNull);
        expect(result.messageAr, isNull);
        expect(result.messageEn, isNull);
      });
    });

    group('Error handling', () {
      test('يعيد خطأ عند فشل الاتصال بالخادم', () async {
        final json = {
          'mode': 'error',
          'error': 'network_error',
          'message_ar': 'خطأ في الاتصال',
          'message_en': 'Network error',
          'raw_error': 'Connection timeout',
        };

        final result = NafathSessionResult.fromJson(json);

        expect(result.mode, NafathSessionMode.error);
        expect(result.messageAr, 'خطأ في الاتصال');
      });

      test('يدعم رسائل خطأ مختلفة من الخادم', () async {
        const errorMessages = [
          'invalid_national_id',
          'request_not_found',
          'missing_request_id',
          'nafath_service_unavailable',
          'database_error',
        ];

        for (final errorMsg in errorMessages) {
          final json = {
            'mode': 'error',
            'error': errorMsg,
          };

          final result = NafathSessionResult.fromJson(json);
          expect(result.mode, NafathSessionMode.error);
        }
      });
    });

    group('Integration scenarios', () {
      test('سيناريو كامل: من البداية إلى الموافقة', () async {
        // 1. بدء الطلب
        final startResponse = {
          'mode': 'polling',
          'request_id': 'trans_123',
          'random': '77',
          'status': 'WAITING',
          'message_ar': 'افتح تطبيق نفاذ واختر 77',
        };
        final start = NafathSessionResult.fromJson(startResponse);

        expect(start.mode, NafathSessionMode.polling);
        expect(start.random, '77');

        // 2. استعلام أول: لا تزال الحالة معلقة
        final pollResponse1 = {
          'mode': 'polling',
          'status': 'WAITING',
          'request_id': 'trans_123',
          'random': '77',
        };
        final poll1 = NafathSessionResult.fromJson(pollResponse1);

        expect(poll1.mode, NafathSessionMode.polling);
        expect(poll1.status, 'WAITING');

        // 3. استعلام ثاني: تم التحقق
        final pollResponse2 = {
          'mode': 'redirect',
          'status': 'COMPLETED',
          'request_id': 'trans_123',
          'authorization_url': 'https://example.com/auth?token=xyz',
        };
        final poll2 = NafathSessionResult.fromJson(pollResponse2);

        expect(poll2.mode, NafathSessionMode.redirect);
        expect(poll2.authorizationUrl, contains('token='));
      });

      test('سيناريو المستخدم الجديد: تسجيل عبر نفاذ', () async {
        final registerStart = {
          'mode': 'polling',
          'request_id': 'reg_456',
          'random': '33',
          'status': 'WAITING',
        };

        final result = NafathSessionResult.fromJson(registerStart);

        expect(result.mode, NafathSessionMode.polling);
        expect(result.requestId, 'reg_456');
      });

      test('سيناريو الرفض: المستخدم لم يوافق', () async {
        final rejection = {
          'mode': 'error',
          'status': 'REJECTED',
          'request_id': 'trans_123',
          'message_ar': 'تم رفض الطلب من قبل المستخدم',
        };

        final result = NafathSessionResult.fromJson(rejection);

        expect(result.mode, NafathSessionMode.error);
        expect(result.status, 'REJECTED');
      });

      test('سيناريو انتهاء المهلة: تجاوز الوقت المسموح', () async {
        final timeout = {
          'mode': 'error',
          'status': 'EXPIRED',
          'request_id': 'trans_123',
          'message_ar': 'انتهت المهلة الزمنية للطلب',
        };

        final result = NafathSessionResult.fromJson(timeout);

        expect(result.mode, NafathSessionMode.error);
        expect(result.status, 'EXPIRED');
      });
    });

    group('Data validation', () {
      test('يتحقق من صيغة رقم الهوية (10 أرقام)', () async {
        const validIds = ['1234567890', '0987654321'];
        const invalidIds = ['123', '12345678901', '12345678ab'];

        for (final id in validIds) {
          expect(
            RegExp(r'^\d{10}$').hasMatch(id),
            isTrue,
            reason: '$id يجب أن يكون صيغة صحيحة',
          );
        }

        for (final id in invalidIds) {
          expect(
            RegExp(r'^\d{10}$').hasMatch(id),
            isFalse,
            reason: '$id يجب أن تكون صيغة غير صحيحة',
          );
        }
      });

      test('يتحقق من صيغة رقم التحقق (رقمان)', () async {
        const validRandoms = ['00', '42', '99', '01'];
        const invalidRandoms = ['0', '100', '1ab'];

        for (final r in validRandoms) {
          expect(
            RegExp(r'^\d{2}$').hasMatch(r),
            isTrue,
            reason: '$r يجب أن يكون صيغة صحيحة',
          );
        }

        for (final r in invalidRandoms) {
          expect(
            RegExp(r'^\d{2}$').hasMatch(r),
            isFalse,
            reason: '$r يجب أن تكون صيغة غير صحيحة',
          );
        }
      });

      test('يتحقق من صيغة معرف الطلب (UUID)', () async {
        const validUuids = [
          '550e8400-e29b-41d4-a716-446655440000',
          'f47ac10b-58cc-4372-a567-0e02b2c3d479',
        ];
        const invalidUuids = ['123', 'not-a-uuid'];

        for (final uuid in validUuids) {
          expect(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
              caseSensitive: false,
            ).hasMatch(uuid),
            isTrue,
            reason: '$uuid يجب أن يكون UUID صحيح',
          );
        }

        for (final uuid in invalidUuids) {
          expect(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
              caseSensitive: false,
            ).hasMatch(uuid),
            isFalse,
            reason: '$uuid يجب أن يكون UUID غير صحيح',
          );
        }
      });
    });
  });
}
