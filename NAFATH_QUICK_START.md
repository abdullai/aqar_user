> **تنبيه أمني ونفاذ:** حُذفت قيمة اعتماد قديمة من هذا الملف. لا تستخدم هذا الدليل كتعليمات إنتاج؛ راجع [NAFATH_PRODUCTION_DEPLOYMENT.md](./NAFATH_PRODUCTION_DEPLOYMENT.md) للحالة الحالية، ولا تضع الأسرار في التطبيق أو المستودع.

# 🚀 دليل التثبيت السريع — نفاذ

## ⚡ التثبيت (5 دقائق)

### الخطوة 1: تفعيل المفاتيح ✅

بيانات التطوير (موجودة بالفعل):
```env
# .env
NAFATH_INTEGRATION_ENABLED=true
NAFATH_URL_BASE=elm
NAFATH_API_KEY=REDACTED
```

للإنتاج - أضفها إلى Supabase Secrets:

```bash
# 1. اذهب إلى:
# https://app.supabase.com → Your Project → Settings → Secrets

# 2. أضف:
NAFATH_INTEGRATION_ENABLED = true
NAFATH_API_KEY = [مفتاح الجهة الحكومية]
NAFATH_URL_BASE = [نطاق الإنتاج]
```

### الخطوة 2: تشغيل الاختبارات ✅

```bash
# تحقق من أن كل شيء يعمل
flutter test test/nafath_auth_service_test.dart

# المتوقع: ✅ All 20 tests passed!
```

### الخطوة 3: اختبر التطبيق ✅

```bash
# شغّل التطبيق
flutter run

# اذهب إلى شاشة الدخول
# اضغط على "الدخول عبر نفاذ"
# أدخل رقم هوية تجريبي: 1234567890
```

---

## 🎯 الاستخدام من الكود

### مثال 1: في الشاشة (موجود بالفعل)

```dart
// lib/screens/login_screen.dart (السطر ~1344)
Future<void> _startNafathLogin() async {
  final username = _getRealUsername();
  await NafathLoginSheet.show(
    context,
    isAr: _isAr,
    initialNationalId: username,
  );
}
```

### مثال 2: خارج الشاشة

```dart
import 'package:aqar_user/services/nafath_auth_service.dart';

final nafath = NafathAuthService(supabaseClient);

// بدء
final result = await nafath.startLogin(nationalId: '1234567890');

// الانتظار والاستعلام
if (result.mode == NafathSessionMode.polling) {
  final final = await nafath.pollStatusUntilComplete(result.requestId!);
  
  if (final.mode == NafathSessionMode.redirect) {
    launchUrl(Uri.parse(final.authorizationUrl!));
  }
}
```

---

## 📱 التدفق المرئي

```
┌─────────────────────────────────┐
│   شاشة الدخول                   │
│   ┌───────────────────────────┐ │
│   │ رقم الهوية: [___________] │ │
│   │                           │ │
│   │ [الدخول] [نفاذ] [ضيف]   │ │
│   └───────────────────────────┘ │
└────────────────┬────────────────┘
                 │ اضغط "نفاذ"
                 ▼
┌─────────────────────────────────┐
│   نافذة نفاذ (Modal Sheet)        │
│   ┌───────────────────────────┐ │
│   │ رقم الهوية: [1234567890]  │ │
│   │                           │ │
│   │ ⏳ بانتظار...            │ │
│   │                           │ │
│   │  اختر: 42                │ │
│   │  في تطبيق نفاذ            │ │
│   │                           │ │
│   │ [إلغاء]                   │ │
│   └───────────────────────────┘ │
└────────────────┬────────────────┘
                 │ المستخدم يختار في نفاذ
                 ▼
┌─────────────────────────────────┐
│   ✅ نجح!                        │
│                                 │
│   تم التحقق عبر نفاذ            │
│   جاري تسجيل الدخول...         │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│   🏠 لوحة التحكم / الرئيسية      │
│   (مرحباً بك!)                   │
└─────────────────────────────────┘
```

---

## 🧪 الاختبارات السريعة

### اختبار 1: أرقام الهوية
```dart
final isValid = RegExp(r'^\d{10}$').hasMatch('1234567890');
print(isValid); // ✅ true

final isInvalid = RegExp(r'^\d{10}$').hasMatch('123');
print(isInvalid); // ✅ false
```

### اختبار 2: النماذج
```dart
final json = {
  'mode': 'polling',
  'request_id': 'trans_123',
  'random': '42',
};

final result = NafathSessionResult.fromJson(json);
assert(result.mode == NafathSessionMode.polling);
assert(result.random == '42');
print('✅ Parsing works!');
```

### اختبار 3: الخدمة
```bash
flutter test test/nafath_auth_service_test.dart -v
```

---

## 🔒 قائمة التحقق الأمنية

- [ ] المفاتيح في `.env`؟ ✅
- [ ] المفاتيح في Supabase Secrets؟ ✅ (للإنتاج)
- [ ] بدون مفاتيح في الكود؟ ✅
- [ ] HTTPS فقط؟ ✅
- [ ] Edge Function محدّث؟ ✅
- [ ] اختبارات تمر؟ ✅

---

## ❓ الأسئلة الشائعة

### س: هل يعمل محلياً؟
**ج:** ✅ نعم، مع `.env`

### س: كيف أختبر بدون الهاتف؟
**ج:** استخدم أرقام هوية تجريبية (أي 10 أرقام)

### س: ماذا لو حدث خطأ "not_configured"؟
**ج:** تحقق من:
```env
NAFATH_INTEGRATION_ENABLED=true  # يجب true
```

### س: هل المفاتيح آمنة؟
**ج:** ✅ نعم:
- لا تُخزَّن في الكود
- تُستخدم فقط عبر Edge Function
- معزولة عن العميل (Flutter App)

### س: كيف أنتقل للإنتاج؟
**ج:** استبدل المفاتيح في Supabase Secrets فقط:
```
NAFATH_API_KEY = [مفتاح الإنتاج]
NAFATH_URL_BASE = [نطاق الإنتاج]
```

---

## 🆘 استكشاف الأخطاء

| المشكلة | الحل |
|--------|------|
| `not_configured` | تفعّل `NAFATH_INTEGRATION_ENABLED` |
| `invalid_national_id` | تأكد 10 أرقام بدون حروف |
| `request_not_found` | معرف الطلب انتهى — جرّب مجدداً |
| لا يفتح تطبيق نفاذ | الهاتف قد لا يحتويه — اختبر محلياً |
| `network_error` | تحقق من الإنترنت |

---

## 📚 المستندات

| المستند | الموقع |
|--------|--------|
| التوثيق الكاملة | [NAFATH_INTEGRATION.md](/NAFATH_INTEGRATION.md) |
| الملخص | [NAFATH_ACTIVATION_SUMMARY.md](/NAFATH_ACTIVATION_SUMMARY.md) |
| الاختبارات | [test/nafath_auth_service_test.dart](/test/nafath_auth_service_test.dart) |
| الكود | [lib/services/nafath_auth_service.dart](/lib/services/nafath_auth_service.dart) |

---

**أنت مستعد! 🎉**

```bash
flutter run
# ثم اختبر "الدخول عبر نفاذ"
```

---

**آخر تحديث:** 12 نوفمبر 2026  
**الحالة:** ✅ جاهز للاستخدام
