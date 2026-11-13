# تصحيح ملخص نفاذ السابق

> **الملخص السابق غير دقيق ولا يثبت جاهزية الإنتاج.** كان يتضمن تحقق توقيع
> HMAC غير مطابق لدليل المنتج، وإنشاء دخول محليًا لا ينشئ جلسة Supabase Auth.

الحالة التنفيذية الحالية وتعليمات النشر في
[`NAFATH_PRODUCTION_DEPLOYMENT.md`](./NAFATH_PRODUCTION_DEPLOYMENT.md)،
وتفاصيل الخدمة في
[`supabase/functions/nafath_callback/README.md`](./supabase/functions/nafath_callback/README.md).

تم تجهيز بوابة سعودية للطلبات والاستعلام وCallback، والتحقق من JWT عبر RS256
وJWK، واختبارها محليًا. لا يزال النشر الفعلي وربط جلسة Supabase Auth معلقين
على بيانات Elm، وخادم سعودي ونطاق يملكه المستخدم، واعتماد تدفق حفظ بيانات
الهوية.
