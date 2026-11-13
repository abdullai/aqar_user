> **تنبيه:** أي عبارة في هذا المستند تفيد بأن تكامل نفاذ جاهز للإنتاج أو مفعّل أصبحت قديمة؛ الحالة الحالية والخطوات في [NAFATH_PRODUCTION_DEPLOYMENT.md](./NAFATH_PRODUCTION_DEPLOYMENT.md).

# ملفات تكامل نفاذ الحالية

> **ملاحظة تصحيح:** هذا الملف يحل محل جرد سابق غير دقيق ذكر HMAC وادعى أن
> التكامل جاهز للإنتاج. Callback يتطلب JWT بـ RS256 كما في دليل المنتج،
> والتحقق من نفاذ لا ينشئ جلسة Supabase Auth وحده.

- البوابة السعودية والاختبارات:
  [`supabase/functions/nafath_callback/`](./supabase/functions/nafath_callback/)
- واجهة التطبيق إلى البوابة:
  [`supabase/functions/nafath_session/index.ts`](./supabase/functions/nafath_session/index.ts)
- ترحيل عمود عنوان IP:
  [`supabase/migrations/20261113000000_nafath_callback_ip.sql`](./supabase/migrations/20261113000000_nafath_callback_ip.sql)
- خدمة Flutter:
  [`lib/services/nafath_auth_service.dart`](./lib/services/nafath_auth_service.dart)
- خطوات النشر والمتطلبات المفتوحة:
  [`NAFATH_PRODUCTION_DEPLOYMENT.md`](./NAFATH_PRODUCTION_DEPLOYMENT.md)

الاختبارات المحلية الحالية: 7 لاختبار الخادم، و6 لاختبار Edge Function،
و36 اختبار Flutter في مجموعتي الاختبار المستهدفتين. هذه اختبارات محلية فقط؛
لم يتم الاتصال ببيئة Elm ولم يتم نشر الخادم.
