# تفعيل نفاذ بعد التحديث

## ما جرى تجهيزه في المشروع

- Edge Function يمرر NSI002/NSI003 إلى خادم نفاذ الخاص في السعودية.
- خادم callback يتحقق من JWT عبر JWK وRS256، ويرفض إعادة الاستخدام.
- قاعدة البيانات تحدّث حالة الطلب وملف المستخدم الموجود عند اكتمال callback الموثق.
- جلسة Supabase تصدر لمرة واحدة لحساب مرتبط برقم الهوية؛ لا يُنشأ حساب جديد تلقائياً.
- واجهة تسجيل الدخول تعرض علامة نفاذ وشعار أقار المتكيف مع التطبيق أو الويب.

## ما يلزم لتشغيل الاتصال الحقيقي

1. **دوّر مفاتيح نفاذ التي ظهرت في الصورة** قبل إعادة استخدامها. لا تلصق المفتاح
   في الكود أو Flutter أو `.env` العميل.
2. احصل من نفاذ على القيم الصحيحة للبيئة المطلوبة: APP-ID وAPP-KEY وAPI host و
   issuer وaudience واعتماد callback.
3. استضف `supabase/functions/nafath_callback` على خادم فعلي داخل السعودية مع
   IP عام ثابت، واضبط متغيرات الخادم الموضحة في README المجاور.
4. سجل عنوان `https://<domain>/callback` لدى نفاذ وتحقق من عناوين IP المسموح بها
   في Caddyfile.
5. أنشئ سرّاً عشوائياً طويلاً لـ `NAFATH_GATEWAY_SECRET` وضع القيمة نفسها على
   الخادم السعودي وSupabase. اضبط `NAFATH_GATEWAY_URL` على رابط الخادم.
6. بعد التحقق من إعدادات البيئة، انشر Edge Function `nafath_session`.

## قاعدة البيانات

ترحيل `20261115040000_nafath_nsi_standards.sql` يضيف حقولاً لتسجيل اللغة و`kid`
ورمز الخطأ ومنع إصدار الجلسة مرتين،
ودالتين محصورتين على دور `service_role`. وظيفة callback لا تخزن JWT الخام أو
claims شخصية غير لازمة.

```powershell
supabase migration list
supabase db push
```

لا تشغّل `db reset` على قاعدة بيانات مشتركة أو إنتاجية. `db push` يطبق كل
الترحيلات المعلقة للمشروع المرتبط، لذا راجع القائمة قبل الموافقة. يوجد حالياً
ترحيل Nafath واحد معلق على المشروع.

## الاختبارات المحلية

```powershell
node --test supabase\functions\nafath_session\index.test.cjs
node --test supabase\functions\nafath_callback\server.test.mjs
flutter test test\nafath_auth_service_test.dart test\nafath_complete_integration_test.dart
```

قبل الإنتاج، اختبر في sandbox: WAITING وCOMPLETED وREJECTED وEXPIRED، الطلب
النشط `400-034-050`، التوقيع الخاطئ، `kid` أو claims غير صحيحة، إعادة callback،
وهوية غير مرتبطة بحساب أقار.

## حدود التفعيل

وجود الكود والترحيل لا ينشر خادم السعودية ولا يفعّل اعتماد نفاذ تلقائياً. لا
يمكن إتمام الاختبار الحقيقي حتى تتوفر مفاتيح مدوّرة وبيانات البيئة واعتماد
callback والاستضافة السعودية. المستخدم الذي لا يملك حساباً مرتبطاً مسبقاً يجب
أن يمر بتدفق التسجيل الحالي.
