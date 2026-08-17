# إشعارات سير العمل (FCM) و REGA — إعداد وتشغيل

## 1) دفع FCM لكل إشعار داخل التطبيق (`in_app_notifications`)

الدالة `workflow_create_notification` (في SQL) تُدرج صفاً في `in_app_notifications` فقط.  
Edge Function **`send_push`** تدعم وضع **Webhook** عند **INSERT** على هذا الجدول وتُرسل FCM للمستخدم المستهدف (حسب `username` → `users_profiles.user_id` → رموز FCM).

### خطوات Supabase (لوحة التحكم)

1. **Authentication → Settings**: تأكد أن المستخدمون لديهم `username` في `users_profiles` يطابق عمود الإشعار (هذا شرط الدالة SQL).
2. **Edge Functions → `send_push`**: نشر الدالة مع أسرار Firebase (`FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY_B64`) ومتغيرات Supabase الخدمية كما في بقية المشروع.
3. **Database → Webhooks** (أو Integrations حسب إصدار المشروع):
   - **Table**: `public.in_app_notifications`
   - **Events**: `INSERT`
   - **HTTP Request**: `POST` إلى  
     `https://<PROJECT_REF>.supabase.co/functions/v1/send_push`
   - **Headers**: `Authorization: Bearer <SERVICE_ROLE_KEY>` و`Content-Type: application/json`
   - **Body**: قالب **Database Webhook** الافتراضي (يحتوي `type`, `table`, `schema`, `record`).

الدالة `send_push` تتجاهل أنواع OTP/PIN/MFA في `type` لأسباب أمنية.

### بيانات التوجيه في الإشعار

يُدمَج حقل `data` (jsonb) للصف مع الحمولة المرسلة إلى FCM، بما فيه:

- `entity_type`, `entity_id` (كما تضيفها `workflow_create_notification`)
- `property_id`, `request_id` إن وُجدت في JSON
- `notification_id` من `in_app_notifications.id` حتى يوسم التطبيق الإشعار كمقروء عند فتح الوجهة.
- عروض طلبات السوق تستخدم `deep_route: market_request` مع `request_id` و`offer_id` عند توفره.

التطبيق (`PushNavigationService`) يعالج `kind: workflow` ويفتح:

- إعلان: `ListingLoaderPage` عند وجود `property_id` أو `entity_type=property`
- طلب تسويق: `ListingRequestStatusPage` عند وجود `request_id` أو `entity_type=listing_request`
- طلب سوق/عرض مهتم: لوحة المستخدم ثم تفاصيل الطلب عند `deep_route=market_request`

### المسار الحالي للعروض والصفقات

- إدراج/تحديث عرض على `market_request_offers` يستدعي `InAppNotificationWriter` في التطبيق، فينشئ صف `in_app_notifications` لصاحب الطلب بنوع `market_request_offer` أو `market_request_offer_updated`.
- قبول/رفض العرض ينشئ إشعاراً لمقدم العرض بنوع `market_request_offer_accepted` أو `market_request_offer_rejected`.
- إتمام طلب السوق ينشئ إشعار `market_request_deal_completed` لمقدم العرض المقبول.
- Realtime داخل التطبيق يشغل الصوت والعداد عبر `InAppNotificationHub`، وWebhook/Outbox يمرر نفس الصف إلى FCM عند تفعيل `send_push`.

## 2) قناة فريق المؤسسة (دردشة جماعية خفيفة)

ليس استبدالاً لجدول `messages` ثنائي الطرف، بل **لوح منشورات** لأعضاء المؤسسة النشطين:

- طبّق SQL: `supabase/sql/20260453_org_team_channel_posts.sql`
- فعّل **Realtime** للجدول `org_team_channel_posts` من لوحة Supabase إن رغبت بالتحديث اللحظي (اختياري؛ التطبيق يدعم السحب للتحديث).

الواجهة: **إدارتي → دردشة الفريق → «قناة الفريق (جماعية)»**.

## 3) طلبات السوق ومحادثات متعددة الأطراف

- **العروض**: عدة مستخدمين يقدّمون عروضاً (`market_request_offers`).
- **الدردشة**: لكل مهتم وصاحب طلب تُنشأ محادثة **1:1** من نوع `market_request` عبر RPC `ensure_market_request_conversation` (انظر `20260411_market_request_chat_offers_v1.sql`).  
  لا توجد «غرفة جماعية» واحدة في المخطط الحالي؛ الواجهة توضح ذلك في بطاقة الطلب.

## 4) REGA / ترخيص الإعلان — مكوّنات المشروع

| المكوّن | الوصف |
|--------|--------|
| `lib/screens/rega_ad_license_import_page.dart` | استيراد/إدخال بيانات ترخيص الإعلان |
| `lib/widgets/rega_ad_license_gate_sheet.dart` | بوابة قبل إضافة إعلان للمسوّق/المنشأة |
| `supabase/functions/verify_fal_license/` | Edge: التحقق من رخصة فال |
| `supabase/sql/*workflow*` و `*permit*` | مراحل التصريح والنشر وربط الإشعارات |

«REGA كاملاً» يعني مطابقة الحقول مع واجهات الهيئة، سياسات RLS، وتشغيل Webhooks/Edge على الإنتاج — هذا الملف يحدد نقاط الربط؛ أي توسعة لاحقة تبقى على نفس المسارات أعلاه.
