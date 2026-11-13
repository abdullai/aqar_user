> **تنبيه أمني ونفاذ:** حُذفت قيمة اعتماد قديمة من هذا الملف. لا تستخدم هذا الدليل كتعليمات إنتاج؛ راجع [NAFATH_PRODUCTION_DEPLOYMENT.md](./NAFATH_PRODUCTION_DEPLOYMENT.md) للحالة الحالية، ولا تضع الأسرار في التطبيق أو المستودع.

# 🔐 تكامل نفاذ (Nafath) — المصادقة الحكومية السعودية

تم تفعيل تكامل **نفاذ** على مشروعك! هذا دليل شامل للاستخدام والتطوير.

## 📋 ما هو نفاذ؟

**نفاذ** هي منصة حكومية سعودية للمصادقة الموثوقة عبر:
- 🔑 رقم الهوية/الإقامة
- 📱 تطبيق نفاذ على الهاتف
- ✅ موافقة أمنية متعددة العوامل

## 🚀 الحالة الحالية

### ✅ تم تفعيله
- ✅ [Edge Function](/supabase/functions/nafath_session/index.ts) — جاهزة للعمل
- ✅ [NafathAuthService](/lib/services/nafath_auth_service.dart) — خدمة Dart كاملة
- ✅ [NafathLoginSheet](/lib/widgets/nafath_login_sheet.dart) — واجهة مستخدم
- ✅ [Nafath Models](/lib/core/government/nafath_models.dart) — نماذج البيانات
- ✅ [اختبارات](/test/nafath_auth_service_test.dart) — اختبارات شاملة

### ⚙️ الإعدادات المطلوبة

#### 1️⃣ في `.env` (للتطوير المحلي)
```env
# التجريبي — موجود بالفعل
NAFATH_INTEGRATION_ENABLED=true
NAFATH_URL_BASE=elm
NAFATH_API_KEY=REDACTED
```

#### 2️⃣ في Supabase Secrets (للإنتاج)
```
Supabase Dashboard → Project Settings → Secrets → Add Secret
```

أضف:
- `NAFATH_INTEGRATION_ENABLED` = `true`
- `NAFATH_API_KEY` = مفتاح من عقد الجهة الحكومية
- `NAFATH_URL_BASE` = نطاق نفاذ الحقيقي

**⚠️ لا تضع المفاتيح في الكود مباشرة!**

## 📱 الاستخدام في التطبيق

### في شاشة الدخول (login_screen.dart)

المستخدم يضغط على زر "الدخول عبر نفاذ" → يُفتح:

```dart
// تم بالفعل: التطبيق يستدعي NafathLoginSheet.show()
await NafathLoginSheet.show(
  context,
  isAr: true,  // اللغة
  initialNationalId: '1234567890',
  rememberMe: true,
);
```

### استخدام الخدمة مباشرة

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aqar_user/services/nafath_auth_service.dart';

// إنشاء الخدمة
final nafathService = NafathAuthService(Supabase.instance.client);

// 1️⃣ بدء عملية الدخول
final startResult = await nafathService.startLogin(
  nationalId: '1234567890',  // 10 أرقام
  locale: 'ar',               // أو 'en'
);

if (startResult.mode == NafathSessionMode.polling) {
  // 2️⃣ عرض رقم التحقق للمستخدم
  print('اختر الرقم: ${startResult.random}');
  print('معرف الطلب: ${startResult.requestId}');
  
  // 3️⃣ الاستعلام عن الحالة حتى الموافقة
  final pollResult = await nafathService.pollStatusUntilComplete(
    startResult.requestId!,
    onProgress: (result) {
      print('الحالة: ${result.status}');
    },
  );
  
  if (pollResult.mode == NafathSessionMode.redirect) {
    // 4️⃣ المستخدم وافق — افتح الرابط
    launchUrl(Uri.parse(pollResult.authorizationUrl!));
  }
}
```

## 🔄 دورة المصادقة الكاملة

```
┌─────────────────────────────────────────────────────────────┐
│  1. المستخدم يدخل رقم الهوية (10 أرقام)                    │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  2. التطبيق يبدأ طلب نفاذ                                  │
│     POST /api/v1/mfa/request                              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  3. نفاذ يعيد: رقم التحقق (مثل: 42) + معرف الطلب            │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  4. عرض الرقم للمستخدم                                     │
│     "اختر 42 في تطبيق نفاذ"                               │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  5. المستخدم يفتح نفاذ ويختار الرقم                       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  6. التطبيق يستعلم عن الحالة (polling)                     │
│     POST /api/v1/mfa/request/status                       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  7. نفاذ يعيد: "WAITING" أو "COMPLETED"                    │
└────────────────────┬────────────────────────────────────────┘
                     │
         ┌───────────┴────────────┐
         │                        │
    WAITING               COMPLETED ✅
         │                        │
         ▼                        ▼
    استعلم مرة أخرى      يعيد رابط تسجيل الدخول
       بعد 2 ثانية        (Magic Link)
         │                        │
         └───────────┬────────────┘
                     │
                     ▼
         ┌─────────────────────────┐
         │  8. افتح الرابط         │
         │  9. تسجيل الدخول        │
         │  10. مرحبا بك!         │
         └─────────────────────────┘
```

## 🧪 الاختبارات

الاختبارات موجودة في: [test/nafath_auth_service_test.dart](/test/nafath_auth_service_test.dart)

تغطي:
- ✅ صيغ البيانات (أرقام الهوية، معرفات الطلبات)
- ✅ حالات النجاح (WAITING → COMPLETED)
- ✅ حالات الخطأ (REJECTED، EXPIRED)
- ✅ معالجة الأخطاء الشبكية
- ✅ السيناريوهات الكاملة

تشغيل الاختبارات:
```bash
flutter test test/nafath_auth_service_test.dart
```

## 📡 Edge Function (`nafath_session`)

الملف: [supabase/functions/nafath_session/index.ts](/supabase/functions/nafath_session/index.ts)

### العمليات المدعومة:

#### 1. `start` — بدء طلب نفاذ
```typescript
POST /functions/v1/nafath_session
Content-Type: application/json

{
  "action": "start",
  "flow": "login",           // أو "register"
  "locale": "ar",            // أو "en"
  "national_id": "1234567890"
}

// العائد:
{
  "mode": "polling",
  "request_id": "trans_123",
  "random": "42",
  "status": "WAITING",
  "message_ar": "افتح نفاذ واختر 42..."
}
```

#### 2. `poll` — الاستعلام عن الحالة
```typescript
POST /functions/v1/nafath_session
Content-Type: application/json

{
  "action": "poll",
  "request_id": "trans_123"
}

// العائد:
{
  "mode": "redirect",  // أو "polling"، "error"
  "status": "COMPLETED",
  "authorization_url": "https://...magic-link..."
}
```

#### 3. `callback` — استقبال رد من نفاذ (مستقبلاً)
```typescript
POST /functions/v1/nafath_session
Content-Type: application/json

{
  "action": "callback",
  "response": "JWT_TOKEN_FROM_NAFATH",
  ...
}
```

## 🔑 بيانات الاختبار

### الحسابات التجريبية (إذا توفرت)
تحقق من لوحة نفاذ التجريبية:
- 🌐 https://elm.semati.sa
- 📖 الوثائق الرسمية

### أرقام الهوية الاختبارية
```
✅ صيغة صحيحة: 1234567890، 0987654321
❌ صيغة خاطئة: 123 (قصير)، 12345678901 (طويل)
```

## 📊 تتبع الطلبات

جميع طلبات نفاذ تُحفظ في جدول: `nafath_logins`

```sql
SELECT 
  trans_id,
  national_id,
  status,
  random,
  created_at,
  updated_at,
  completed_at
FROM nafath_logins
WHERE national_id = '1234567890'
ORDER BY created_at DESC
LIMIT 10;
```

## 🐛 التصحيح والتطوير

### تفعيل السجلات (Logging)
```dart
// في NafathAuthService
Future<NafathSessionResult> startSession({...}) async {
  print('🔵 بدء طلب نفاذ: $nationalId');
  try {
    final res = await _sb.functions.invoke(...);
    print('✅ استجابة نفاذ: ${res.data}');
    return NafathSessionResult.fromJson(Map<String, dynamic>.from(data));
  } catch (e) {
    print('❌ خطأ نفاذ: $e');
    return ...
  }
}
```

### اختبار Edge Function محلياً
```bash
# بدء Supabase محليًا
supabase start

# اختبر الدالة مباشرة
curl -X POST http://127.0.0.1:54321/functions/v1/nafath_session \
  -H "Authorization: Bearer $(supabase status | grep 'anon key' | awk '{print $NF}')" \
  -H "Content-Type: application/json" \
  -d '{"action":"start","flow":"login","locale":"ar","national_id":"1234567890"}'
```

## ⚠️ ملاحظات أمنية

1. **لا تخزن المفاتيح في الكود:**
   ```dart
   ❌ const NAFATH_API_KEY = 'REDACTED';  // خطر!
   ✅ Deno.env.get('NAFATH_API_KEY')      // آمن
   ```

2. **استخدم HTTPS فقط:**
   ```dart
   ❌ http://nafath.api.com
   ✅ https://mock-service.api.elm.sa
   ```

3. **تحقق من معرف الطلب:**
   ```dart
   if (!/^[a-f0-9\-]{8,}$/.test(requestId)) {
     return error('invalid_request_id');
   }
   ```

4. **حدّد انتهاء الصلاحية:**
   ```dart
   // طلب نفاذ ينتهي بعد 2-3 دقائق
   // طبّق timeout محلي: 3 دقائق
   Future.delayed(Duration(minutes: 3));
   ```

## 🚦 حالات الخطأ الشائعة

| الخطأ | السبب | الحل |
|-------|------|------|
| `invalid_national_id` | رقم الهوية ليس 10 أرقام | تحقق من الصيغة |
| `request_not_found` | معرف الطلب غير موجود | جرّب من الجديد |
| `REJECTED` | المستخدم رفض على نفاذ | اطلب من المستخدم التجربة مرة أخرى |
| `EXPIRED` | انتهت المهلة الزمنية | أعد محاولة البدء من الجديد |
| `network_error` | لا اتصال بالإنترنت | تحقق من الاتصال |
| `not_configured` | المفاتيح غير مفعلة | أضفها إلى Supabase Secrets |

## 📚 الموارد

- 📖 [وثائق نفاذ الرسمية](https://nafath.gov.sa)
- 🌐 [لوحة نفاذ التجريبية](https://elm.semati.sa)
- 💾 [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- 🦀 [Deno (لكتابة Edge Functions)](https://deno.land)

## ✨ التحسينات المستقبلية

- [ ] دعم المصادقة البيومترية (Face ID / بصمة)
- [ ] ربط متعدد الحسابات (عائلة)
- [ ] تذكر الهوية للدخول السريع
- [ ] دعم QR Code من نفاذ
- [ ] عمليات تحقق إضافية (كشف الهوية)

## 🆘 الدعم

للمساعدة:
1. اطلع على الاختبارات: [nafath_auth_service_test.dart](/test/nafath_auth_service_test.dart)
2. فعّل السجلات (console logs)
3. تحقق من استجابة Edge Function
4. ابحث في سجل `nafath_logins`

---

**آخر تحديث:** نوفمبر 2026  
**الحالة:** ✅ تجريبي جاهز للاستخدام  
**الإصدار:** 1.0.0
