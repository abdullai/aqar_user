# تكامل نفاذ NSI في أقار

## المعمارية الفعلية

```text
تطبيق أقار
  -> Supabase Edge Function: nafath_session
  -> خادم Nafath خاص مستضاف في السعودية
  -> Nafath API (NSI002 / NSI003 / NSI001)

Nafath callback
  -> خادم السعودية: /callback
  -> تحقق RS256 و kid و issuer/audience والمهلة
  -> RPC موثوق يحدّث nafath_logins و users_profiles
  -> Edge Function يصدر جلسة Supabase لمستخدم أقار موجود ومطابق للهوية
```

الخادم السعودي هو المكان الوحيد الذي يتعامل مع APP-ID وAPP-KEY وJWT. لا
يحتوي تطبيق Flutter على مفاتيح نفاذ، ولا يثق بنتيجة COMPLETED من NSI003 وحدها:
يجب أن يصل callback صحيح وموقّع أولاً.

## مراحل التكامل

### NSI002 — بدء طلب MFA

يرسل التطبيق رقم الهوية إلى `nafath_session`، التي تنشئ UUID داخلياً وتحفظ
المعاملة بعد أن يرسل الخادم السعودي:

```http
POST /api/v1/mfa/request?local=ar&requestId=<UUID>
APP-ID: <server secret>
APP-KEY: <server secret>
X-Forwarded-For: <client-ip>,<saudi-server-ip>
Content-Type: application/json
```

```json
{"nationalId":"<10-digit-id>","service":"Login"}
```

يعرض التطبيق قيمة `random` الواردة من نفاذ. خطأ `400-034-050` يعاد كحالة
تعارض مع رسالة تفيد بوجود طلب نشط.

### NSI003 — استعلام الحالة

كل استعلام يمر عبر الخادم السعودي ويستخدم رقم الهوية و`transId` و`random`.
يتعامل التطبيق مع WAITING وCOMPLETED وREJECTED وEXPIRED. حالة COMPLETED من
NSI003 لا تكفي للدخول حتى يتحقق الخادم من callback الموقّع.

### NSI001 وCallback — التحقق وإنهاء الدخول

يستقبل `/callback` قيم `requestId` و`transId` وJWT. يجلب الخادم مفاتيح
`/api/v1/mfa/jwk`، يطابق `kid`، ويتحقق من توقيع RS256 والـ claims المطلوبة.
بعدها تنفذ دالة قاعدة البيانات معاملة ذرية لتثبيت الحالة وتحديث أعمدة
`nafath_verified_at` و`auth_method` في ملف المستخدم المطابق. لا يُحفظ JWT الخام.

بعدها تصدر Edge Function جلسة Auth لمستخدم موجود مرتبط برقم الهوية عبر
Supabase Auth magic link لمرة واحدة. إذا لم يوجد ملف مستخدم واحد مطابق، لا
ينشئ التكامل حساباً جديداً ولا يصدر جلسة؛ يجب التسجيل أولاً عبر المسار الحالي.

## الإعداد السري

### Supabase Edge Function secrets

```text
NAFATH_GATEWAY_URL=https://<public-saudi-host>
NAFATH_GATEWAY_SECRET=<random-secret-32-characters-or-more>
```

المفتاح نفسه يستخدمه الخادم السعودي لمصادقة طلبات `/nafath/start` و
`/nafath/status`. عنوان Supabase ومفتاحيه العام/الخدمي يوفرهما بيئة Supabase
للـ Edge Function.

### متغيرات الخادم السعودي

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
NAFATH_BASE_URL
NAFATH_APP_ID
NAFATH_APP_KEY
NAFATH_AUDIENCE
NAFATH_ISSUER
NAFATH_SERVICE_PROVIDER_IP
NAFATH_GATEWAY_SECRET
```

ضع القيم المعتمدة بعد تدوير أي مفاتيح ظهرت في صورة أو محادثة. لا تضع مفاتيح
نفاذ أو `SUPABASE_SERVICE_ROLE_KEY` في Flutter أو ملف `.env` الخاص بالتطبيق.

## النشر والتحقق

1. طبّق ترحيلات Supabase المعلقة فقط بعد مراجعة `supabase migration list`.
2. انشر Edge Function `nafath_session` بعد ضبط أسرار الـ gateway.
3. انشر `supabase/functions/nafath_callback` على مضيف فعلي داخل السعودية.
4. سجل عنوان callback العام لدى نفاذ وتحقق من قائمة IP في `Caddyfile`.
5. اختبر الموافقة والرفض والانتهاء والتوقيع الخاطئ و`kid` غير المعروف وaudience
   أو issuer الخاطئ وإعادة إرسال callback.

الاختبارات المحلية:

```powershell
node --test supabase\functions\nafath_session\index.test.cjs
node --test supabase\functions\nafath_callback\server.test.mjs
flutter test test\nafath_auth_service_test.dart test\nafath_complete_integration_test.dart
```

يتطلب التشغيل الحقيقي مفاتيح جديدة غير مكشوفة، واستضافة الخادم السعودي، وموافقة
نفاذ على callback. الاختبارات المحلية لا تنشر هذه الخدمات ولا تستبدل اعتماد نفاذ.
