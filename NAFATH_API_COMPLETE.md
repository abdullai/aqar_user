# تكامل نفاذ — الحالة الحالية وواجهات الخدمة

> **تنبيه:** التحقق من الهوية لا ينشئ جلسة Supabase Auth حتى الآن. لا تعرض
> التطبيق على أنه يسجل دخولًا بنجاح، ولا تنشره للإنتاج قبل إكمال جلسة الدخول
> ومراجعة نقل بيانات الهوية. تعليمات النشر المعتمدة في
> [`NAFATH_PRODUCTION_DEPLOYMENT.md`](./NAFATH_PRODUCTION_DEPLOYMENT.md).

## التدفق

1. يستدعي Flutter دالة Supabase `nafath_session` لبدء طلب أو الاستعلام.
2. ترسل الدالة الطلب إلى البوابة السعودية عبر
   `NAFATH_GATEWAY_URL/nafath/start` أو `/nafath/status`. تستخدم البوابة
   `APP-ID` و`APP-KEY` من أسرار الخادم، وتضيف رأس `X-Forwarded-For`.
3. يتلقى التطبيق رقم التحقق `random` ويعرضه للمستخدم.
4. يستقبل الخادم السعودي Callback على `/callback`، ويتحقق من JWT بخوارزمية
   `RS256` ومفتاح `kid` من JWK، ومن `iss` و`aud` و`transId` وحالة الطلب.
5. يحدّث حالة المعاملة المطابقة فقط. لا يخزّن JWT أو بيانات المستخدم الواردة
   في Callback.
6. بعد `COMPLETED` لا تصدر جلسة دخول حاليًا؛ تعيد الخدمة
   `nafath_auth_session_not_configured` بدل إنشاء جلسة وهمية.

## واجهات التطبيق

### بدء الطلب

`POST /functions/v1/nafath_session`

```json
{
  "action": "start",
  "national_id": "1234567890",
  "flow": "login",
  "locale": "ar"
}
```

الرد قيد الانتظار يتضمن `mode: "polling"` و`request_id` و`random`.

### الاستعلام

`POST /functions/v1/nafath_session`

```json
{
  "action": "poll",
  "request_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

الحالات المتوقعة: `WAITING`، `REJECTED`، `EXPIRED`، `COMPLETED`.
الموافقة وحدها لا تعني أن التطبيق سجّل المستخدم دخوله.

## واجهات الخادم السعودي

- `POST /nafath/start`: داخلية، تتطلب
  `Authorization: Bearer <NAFATH_GATEWAY_SECRET>`. تقبل `requestId`,
  `nationalId`, `service`, `locale`, و`clientIp`.
- `POST /nafath/status`: داخلية، تتطلب السر نفسه. تعيد الحالة فقط، ولا تعيد
  خصائص الهوية إلى Supabase.
- `POST /callback`: عامة لنفاذ، ويقيّدها Caddy بعناوين المصدر المعتمدة في
  دليل المنتج. الشكل الوارد هو `requestId` و`transId` و`token` الموقّع.
- `GET /healthz`: فحص جاهزية الإعداد، دون عرض الأسرار.

## المتغيرات السرية

على **الخادم السعودي فقط**:

- `NAFATH_APP_ID`, `NAFATH_APP_KEY`
- `NAFATH_BASE_URL`, `NAFATH_JWK_URL`
- `NAFATH_ISSUER`, `NAFATH_AUDIENCE`
- `NAFATH_SERVICE_PROVIDER_IP`
- `NAFATH_GATEWAY_SECRET`
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`

في **Supabase Edge Function Secrets**:

- `NAFATH_GATEWAY_URL`
- `NAFATH_GATEWAY_SECRET` (القيمة نفسها على الخادم)
- الأسرار المعتادة لـ Supabase

لا تضع `APP-KEY` أو `SUPABASE_SERVICE_ROLE_KEY` أو سر البوابة في تطبيق Flutter
أو ملفات Git.

## ترحيل قاعدة البيانات

شغّل مرة واحدة على مشروع Supabase:

`supabase/migrations/20261113000000_nafath_callback_ip.sql`

يضيف العمود `client_ip` ليرسل الخادم عنوان العميل المطلوب في ترويسة Nafath.

## التحقق محليًا

```powershell
Push-Location supabase\functions\nafath_callback
npm test
Pop-Location
node --test supabase\functions\nafath_session\index.test.cjs
flutter test --no-pub test\nafath_complete_integration_test.dart test\nafath_auth_service_test.dart
```

## ما لم يكتمل بعد

- لم تُضف بيانات اعتماد Elm/رابط/JWK أو قيم `iss` و`aud` الفعلية؛ احصل عليها
  من منصة رابط، ولا ترسلها في المحادثة.
- لم يُنشأ حساب خادم أو نطاق أو شهادة TLS؛ يلزم حساب المزوّد وموافقتك على
  أي تكلفة.
- التطبيق الحالي يحفظ رقم الهوية وعنوان IP في Supabase خارج السعودية. اعتمد
  تدفق البيانات نظاميًا أو انقل البيانات المطلوبة قبل الإنتاج.
- يلزم تحديد طريقة ربط هوية نفاذ بحساب قائم/جديد وإصدار جلسة Supabase Auth
  موثوقة. لا تستخدم `authorization_url` أو `accessToken` وهميًا.
