# البدء السريع لتجهيز نفاذ

> **ليس جاهزًا للإنتاج بعد.** لا تنشر Callback على Supabase؛ يلزم أن يكون
> الخادم نفسه داخل السعودية، كما أن نجاح تحقق نفاذ لا ينشئ جلسة دخول للتطبيق
> قبل إعداد تدفق Supabase Auth موثوق.

1. احصل من Elm على مفاتيح البيئة التجريبية، رابط JWK، وقيمتي `iss` و`aud`.
2. جهّز خادمًا في الرياض أو جدة بعنوان IP عام ثابت ونطاق HTTPS.
3. اتبع خطوات النشر في
   [`NAFATH_PRODUCTION_DEPLOYMENT.md`](./NAFATH_PRODUCTION_DEPLOYMENT.md).
4. شغّل اختبارات الخدمة من
   `supabase/functions/nafath_callback` باستخدام `npm test`.
5. اختبر مع Elm، ثم أكمل ربط المصادقة بحساب حقيقي قبل إطلاق التطبيق.

لا تضع `APP-KEY` أو `SUPABASE_SERVICE_ROLE_KEY` في التطبيق أو Git أو المحادثة.
