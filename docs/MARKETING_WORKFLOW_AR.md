# مسار المسوق العقاري — ملخص تنفيذي

> **المواصفة الكاملة (نقاط المنتج المترابطة + حالة كل بند):** راجع [`MARKETING_FULL_FLOW_USER_SPEC_AR.md`](MARKETING_FULL_FLOW_USER_SPEC_AR.md).

## ما يعمل في التطبيق حاليًا

1. **إنشاء إعلان / طلب** → يظهر للمسوق في تبويب الدعوات (حسب `listing_requests` و`listing_request_invites`).
2. **إرسال عرض** من صفحة تفاصيل الدعوة → يُستدعى `marketer_submit_offer` (RPC) + تحديث الدعوة + **إشعار داخل التطبيق** للمعلن (`notifyOwnerNewMarketingOffer`).
3. **المعلن** يفتح **عروض المسوقين** من `OwnerOffersPage` (المسار `AppRoutes.ownerOffers` يعمل الآن مع `requestId` و`lang`).
   - **موافقة واختيار** → `owner_select_offer`.
   - **رفض** → تحديث `listing_offers.status = declined` (يتطلب RLS يسمح لصاحب الطلب).
4. **بعد اكتمال توقيع العقد** (كلا الطرفين في `listing_contracts`) → حالة الطلب تصبح **`awaiting_permits`** ويُضبط **`permits_due_at`** = الآن + **72 ساعة** (بدل الانتقال المباشر إلى `published`).
5. **رفع التصاريح / بيانات REGA** من `SubmitPermitsPage` (مسار `AppRoutes.submitPermits`) مع حقول أساسية + **صورة QR إلزامية** ورفعها للتخزين، ثم `submit_permits` (RPC).

## الخصوصية — رقم الجوال

في **تفاصيل الإعلان العامة**: لا يُعرض رقم الجوال إلا **لمالك الإعلان** بعد تسجيل الدخول؛ باقي المستخدمين يُوجَّهون لاستخدام **الدردشة**.

## ما يحتاج إكمالًا لاحقًا

- **توقيع إلكتروني مطبوع** على نص العقد (حقل توقيع في الملف الشخصي).
- **جلب تلقائي** من صفحة REGA لكل حقل (حاليًا: فتح الموقع + إدخال يدوي؛ يمكن إضافة Edge Function إذا توفّر API رسمي).
- **علامة توثيق + اسم المكتب** على بطاقة الإعلان بعد التحقق (`rega_license_snapshot` أو أعمدة مخصصة).
- **طلب إطلاع المعلن على دردشات المسوق**: جدول `listing_chat_visibility_requests` في SQL المرفق + واجهة موافقة.

## Supabase

نفّذ ملفات SQL تحت `supabase/sql/` حسب ترتيبك. راجع [لوحة Supabase](https://supabase.com/dashboard/org) للـ RLS والـ Storage buckets (`property-images` لمسار QR).
