-- =============================================================================
-- تدقيق بيانات مقابل تطبيق aqar_user (معاينة فقط — لا تحديث)
-- =============================================================================
--
-- ⚠️ «كامل البيانات» = نسخ احتياطي للقاعدة (pg_dump / Dashboard backup)، وليس SELECT واحد.
-- هذا الملف: استعلامات تُظهر صفوفاً ناقصة، يتيمة، أو غير متوافقة مع منطق التطبيق
-- لتقرر التعبئة يدوياً أو عبر سكربتات منفصلة بعد مراجعة النتائج.
--
-- نفّذ في Supabase → SQL Editor. راجع كل قسم؛ إن فشل استعلام لغياب جدول/عمود، علّقه أو طبّق migration الناقص أولاً.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0) مخطط سريع: جداول public وعدد الصفوف التقريبي
-- -----------------------------------------------------------------------------
SELECT
  c.relname AS table_name,
  c.reltuples::bigint AS approx_row_count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
ORDER BY c.reltuples DESC NULLS LAST;

-- -----------------------------------------------------------------------------
-- 1) مستخدمون في auth بدون صف في users_profiles (يكسر تدفق التطبيق)
-- -----------------------------------------------------------------------------
SELECT u.id AS auth_user_id, u.email, u.created_at AS auth_created_at
FROM auth.users u
LEFT JOIN public.users_profiles up ON up.user_id = u.id
WHERE up.user_id IS NULL
ORDER BY u.created_at DESC
LIMIT 200;

-- -----------------------------------------------------------------------------
-- 2) users_profiles: مفاتيح ناقصة يعتمد عليها RLS والإشعارات
-- -----------------------------------------------------------------------------
SELECT user_id, username, phone, account_type
FROM public.users_profiles
WHERE username IS NULL
   OR trim(username::text) = ''
LIMIT 200;

-- -----------------------------------------------------------------------------
-- 3) عقارات: مالك بلا ملف users_profiles (أسماء/صلاحيات قد تفشل)
-- -----------------------------------------------------------------------------
SELECT p.id AS property_id, p.owner_id, p.status, p.title
FROM public.properties p
LEFT JOIN public.users_profiles up ON up.user_id = p.owner_id
WHERE up.user_id IS NULL
LIMIT 200;

-- -----------------------------------------------------------------------------
-- 4) صور عقار يتيمة (property_id غير موجود)
-- -----------------------------------------------------------------------------
SELECT pi.id, pi.property_id, pi.path
FROM public.property_images pi
LEFT JOIN public.properties p ON p.id = pi.property_id
WHERE p.id IS NULL
LIMIT 200;

-- -----------------------------------------------------------------------------
-- 5) طلبات تسويق: مالك غير موجود في users_profiles
-- -----------------------------------------------------------------------------
SELECT lr.id AS request_id, lr.owner_id, lr.status, lr.workflow_stage
FROM public.listing_requests lr
LEFT JOIN public.users_profiles up ON up.user_id = lr.owner_id
WHERE up.user_id IS NULL
LIMIT 200;

-- -----------------------------------------------------------------------------
-- 6) عقد موقّع بدون offer_id أو بدون تطابق selected_offer_id (publish_from_contract يفشل)
-- -----------------------------------------------------------------------------
SELECT
  c.id AS contract_id,
  c.request_id,
  c.offer_id AS contract_offer_id,
  r.selected_offer_id AS request_selected_offer_id,
  c.status::text AS contract_status
FROM public.listing_contracts c
JOIN public.listing_requests r ON r.id = c.request_id
WHERE lower(trim(c.status::text)) = 'signed'
  AND (
    c.offer_id IS NULL
    OR c.offer_id IS DISTINCT FROM r.selected_offer_id
  )
LIMIT 200;

-- -----------------------------------------------------------------------------
-- 7) طلب يشير إلى contract_id غير موجود
-- -----------------------------------------------------------------------------
SELECT lr.id AS request_id, lr.contract_id
FROM public.listing_requests lr
LEFT JOIN public.listing_contracts c ON c.id = lr.contract_id
WHERE lr.contract_id IS NOT NULL
  AND c.id IS NULL
LIMIT 200;

-- -----------------------------------------------------------------------------
-- 8) عروض مرتبطة بطلب محذوف أو مفقود
-- -----------------------------------------------------------------------------
SELECT o.id AS offer_id, o.request_id, o.status::text AS offer_status
FROM public.listing_offers o
LEFT JOIN public.listing_requests lr ON lr.id = o.request_id
WHERE lr.id IS NULL
LIMIT 200;

-- -----------------------------------------------------------------------------
-- 9) دعوات مسوّق بدون طلب
-- -----------------------------------------------------------------------------
SELECT inv.id, inv.request_id, inv.marketer_id, inv.status::text
FROM public.listing_request_invites inv
LEFT JOIN public.listing_requests lr ON lr.id = inv.request_id
WHERE lr.id IS NULL
LIMIT 200;

-- -----------------------------------------------------------------------------
-- 10) in_app_notifications: user_id فارغ مع username (يفضّل التطبيق الاثنين)
--     (تعبئة مقترحة كانت في 20260404_app_db_alignment_and_maintenance.sql)
-- -----------------------------------------------------------------------------
SELECT n.id, n.username, n.user_id, n.type, n.created_at
FROM public.in_app_notifications n
WHERE n.username IS NOT NULL
  AND trim(n.username::text) <> ''
  AND n.user_id IS NULL
ORDER BY n.created_at DESC
LIMIT 200;

-- -----------------------------------------------------------------------------
-- 11) marketer_profiles بدون users_profiles (عرض الأسماء)
-- -----------------------------------------------------------------------------
SELECT mp.user_id
FROM public.marketer_profiles mp
LEFT JOIN public.users_profiles up ON up.user_id = mp.user_id
WHERE up.user_id IS NULL
LIMIT 200;

-- -----------------------------------------------------------------------------
-- 12) عضوية منشأة بدون users_profiles
-- -----------------------------------------------------------------------------
SELECT m.org_id, m.user_id, m.status::text
FROM public.org_memberships m
LEFT JOIN public.users_profiles up ON up.user_id = m.user_id
WHERE up.user_id IS NULL
LIMIT 200;

-- -----------------------------------------------------------------------------
-- 13) حجوزات: عقار أو مستخدم مفقود
-- -----------------------------------------------------------------------------
SELECT r.id, r.user_id, r.property_id, r.status::text
FROM public.reservations r
LEFT JOIN public.properties p ON p.id = r.property_id
LEFT JOIN public.users_profiles up ON up.user_id = r.user_id
WHERE p.id IS NULL OR up.user_id IS NULL
LIMIT 200;

-- -----------------------------------------------------------------------------
-- 14) محادثات/رسائل: مراجع مكسورة (إن وُجدت الجداول)
-- -----------------------------------------------------------------------------
SELECT c.id, c.user_id, c.property_id
FROM public.conversations c
LEFT JOIN public.properties p ON p.id = c.property_id
WHERE c.property_id IS NOT NULL AND p.id IS NULL
LIMIT 100;

-- -----------------------------------------------------------------------------
-- 15) طلبات: حالة «عروض وصلت» لكن workflow_stage ما زال قبل اختيار مسوّق (اختياري)
-- -----------------------------------------------------------------------------
SELECT lr.id, lr.status, lr.workflow_stage, lr.updated_at
FROM public.listing_requests lr
WHERE lower(trim(coalesce(lr.status::text, ''))) = 'offers_received'
  AND lower(trim(coalesce(lr.workflow_stage::text, ''))) IN ('waiting_marketers', '')
LIMIT 200;

-- -----------------------------------------------------------------------------
-- 16) وظائف RPC يستدعيها التطبيق — هل موجودة في public؟
-- -----------------------------------------------------------------------------
SELECT p.proname AS function_name
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'reserve_property',
    'publish_property_from_contract',
    'create_listing_contract_from_offer',
    'ensure_my_org_unit',
    'my_org_context',
    'ack_profile_data_revision'
  )
ORDER BY p.proname;

-- =============================================================================
-- بعد المراجعة: عالج كل قسم حسب الحاجة (INSERT/UPDATE/DELETE) في سكربت منفصل
-- ولا تنفّذ تحديثات جماعية دون نسخة احتياطية.
-- =============================================================================
