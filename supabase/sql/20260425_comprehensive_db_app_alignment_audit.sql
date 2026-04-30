-- =============================================================================
-- تدقيق شامل: مخطط + RLS/صلاحيات + بيانات مقابل تطبيق aqar_user
-- =============================================================================
-- معاينة فقط (SELECT). لا يُحدّث البيانات. نفّذ في Supabase → SQL Editor.
-- يبني على: 20260424_app_data_alignment_audit.sql ويوسّعه.
--
-- أقسام:  A أعمدة ناقصة   B سياسات RLS   C منح authenticated
--          D بيانات مستخدمين/إشعارات   E عقارات قديمة/ناقصة
--          F تسويق (طلبات/عقود/عروض)   G حجوزات ومحادثات   H RPC
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- A) أعمدة متوقّعة من الكود/الـ migrations وغير موجودة في public (يجب migration)
-- ═══════════════════════════════════════════════════════════════════════════
WITH expected (tbl, col) AS (
  VALUES
    -- users_profiles (شائعة في التطبيق)
    ('users_profiles', 'user_id'),
    ('users_profiles', 'username'),
    ('users_profiles', 'account_type'),
    ('users_profiles', 'verification_status'),
    ('users_profiles', 'role'),
    ('users_profiles', 'status'),
    ('users_profiles', 'phone'),
    ('users_profiles', 'full_name'),
    ('users_profiles', 'full_name_ar'),
    ('users_profiles', 'full_name_en'),
    ('users_profiles', 'first_name_ar'),
    ('users_profiles', 'fourth_name_ar'),
    ('users_profiles', 'first_name_en'),
    ('users_profiles', 'fourth_name_en'),
    ('users_profiles', 'email'),
    ('users_profiles', 'national_id'),
    ('users_profiles', 'org_id'),
    ('users_profiles', 'public_member_id'),
    ('users_profiles', 'profile_data_revision'),
    ('users_profiles', 'avatar_url'),
    ('users_profiles', 'unified_national_number'),
    ('users_profiles', 'fcm_token'),
    ('users_profiles', 'must_change_password'),
    ('users_profiles', 'terms_version_accepted'),
    -- properties
    ('properties', 'id'),
    ('properties', 'owner_id'),
    ('properties', 'title'),
    ('properties', 'status'),
    ('properties', 'type'),
    ('properties', 'price'),
    ('properties', 'city'),
    ('properties', 'description'),
    ('properties', 'workflow_stage'),
    ('properties', 'request_id'),
    ('properties', 'is_featured'),
    ('properties', 'published_by_marketer_id'),
    ('properties', 'views'),
    -- property_images
    ('property_images', 'property_id'),
    ('property_images', 'path'),
    ('property_images', 'sort_order'),
    -- listing_requests
    ('listing_requests', 'id'),
    ('listing_requests', 'owner_id'),
    ('listing_requests', 'status'),
    ('listing_requests', 'workflow_stage'),
    ('listing_requests', 'selected_offer_id'),
    ('listing_requests', 'selected_marketer_id'),
    ('listing_requests', 'contract_id'),
    ('listing_requests', 'preview_property_id'),
    ('listing_requests', 'marketing_round'),
    -- listing_offers / contracts / invites / permits
    ('listing_offers', 'id'),
    ('listing_offers', 'request_id'),
    ('listing_offers', 'marketer_id'),
    ('listing_offers', 'status'),
    ('listing_contracts', 'id'),
    ('listing_contracts', 'request_id'),
    ('listing_contracts', 'offer_id'),
    ('listing_contracts', 'owner_id'),
    ('listing_contracts', 'marketer_id'),
    ('listing_contracts', 'status'),
    ('listing_request_invites', 'request_id'),
    ('listing_request_invites', 'marketer_id'),
    ('listing_permits', 'request_id'),
    -- in_app_notifications
    ('in_app_notifications', 'id'),
    ('in_app_notifications', 'username'),
    ('in_app_notifications', 'user_id'),
    ('in_app_notifications', 'type'),
    ('in_app_notifications', 'title'),
    ('in_app_notifications', 'body'),
    ('in_app_notifications', 'data'),
    ('in_app_notifications', 'created_at'),
    ('in_app_notifications', 'is_read'),
    -- reservations
    ('reservations', 'user_id'),
    ('reservations', 'property_id'),
    ('reservations', 'status'),
    ('reservations', 'expires_at')
),
tbl_exists AS (
  SELECT table_name
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND table_type = 'BASE TABLE'
)
SELECT e.tbl AS table_missing_or_column_missing,
       e.col AS expected_column
FROM expected e
JOIN tbl_exists t ON t.table_name = e.tbl
LEFT JOIN information_schema.columns c
  ON c.table_schema = 'public'
 AND c.table_name = e.tbl
 AND c.column_name = e.col
WHERE c.column_name IS NULL
ORDER BY e.tbl, e.col;

-- جداول متوقّعة بالكامل غير موجودة في public
WITH need (tbl) AS (
  VALUES
    ('users_profiles'),
    ('properties'),
    ('property_images'),
    ('listing_requests'),
    ('listing_offers'),
    ('listing_contracts'),
    ('listing_request_invites'),
    ('in_app_notifications'),
    ('marketer_profiles'),
    ('reservations')
)
SELECT n.tbl AS table_completely_missing
FROM need n
LEFT JOIN information_schema.tables t
  ON t.table_schema = 'public' AND t.table_type = 'BASE TABLE' AND t.table_name = n.tbl
WHERE t.table_name IS NULL
ORDER BY 1;


-- ═══════════════════════════════════════════════════════════════════════════
-- B) سياسات RLS على الجداول الحسّاسة (مراجعة تعارض/ازدواجية)
-- ═══════════════════════════════════════════════════════════════════════════
SELECT
  tablename,
  policyname,
  cmd AS command,
  roles::text AS roles,
  left(coalesce(qual, ''), 220) AS using_expr_prefix
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'users_profiles',
    'profiles',
    'properties',
    'property_images',
    'listing_requests',
    'listing_offers',
    'listing_contracts',
    'listing_request_invites',
    'listing_permits',
    'in_app_notifications',
    'reservations',
    'conversations',
    'messages',
    'org_memberships',
    'org_units',
    'marketer_profiles'
  )
ORDER BY tablename, policyname;

-- عدد السياسات لكل جدول (ازدواج كثير قد يلتبس عند الصيانة)
SELECT tablename, count(*)::int AS policy_count
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'users_profiles',
    'in_app_notifications',
    'properties',
    'listing_requests'
  )
GROUP BY tablename
ORDER BY policy_count DESC, tablename;


-- ═══════════════════════════════════════════════════════════════════════════
-- C) منح الجداول لدور authenticated (يجب أن يشمل SELECT على ما يقرأه التطبيق)
-- ═══════════════════════════════════════════════════════════════════════════
SELECT
  table_name,
  string_agg(DISTINCT privilege_type, ', ' ORDER BY privilege_type) AS grants
FROM information_schema.role_table_grants
WHERE grantee = 'authenticated'
  AND table_schema = 'public'
  AND table_name IN (
    'users_profiles',
    'profiles',
    'properties',
    'property_images',
    'listing_requests',
    'listing_offers',
    'listing_contracts',
    'listing_request_invites',
    'listing_permits',
    'in_app_notifications',
    'reservations',
    'conversations',
    'messages',
    'marketer_profiles',
    'org_memberships',
    'org_units',
    'account_profiles',
    'user_push_tokens',
    'verification_requests'
  )
GROUP BY table_name
ORDER BY table_name;

-- جداول مذكورة أعلاه وغير ظاهرة = لا منح مباشر (قد يعتمد على RLS فقط أو الجدول غير موجود)
WITH need (tname) AS (
  SELECT unnest(ARRAY[
    'users_profiles','properties','property_images','listing_requests',
    'listing_offers','listing_contracts','in_app_notifications','reservations'
  ]::text[])
)
SELECT n.tname AS table_name,
       CASE WHEN g.table_name IS NULL THEN 'no row in role_table_grants for authenticated' ELSE 'ok' END AS grant_visibility
FROM need n
LEFT JOIN (
  SELECT DISTINCT table_name
  FROM information_schema.role_table_grants
  WHERE grantee = 'authenticated' AND table_schema = 'public'
) g ON g.table_name = n.tname
ORDER BY n.tname;


-- ═══════════════════════════════════════════════════════════════════════════
-- D) مستخدمون وملفات وإشعارات (جودة البيانات)
-- ═══════════════════════════════════════════════════════════════════════════

-- D1) auth.users بدون users_profiles
SELECT u.id AS auth_user_id, u.email, u.created_at
FROM auth.users u
LEFT JOIN public.users_profiles up ON up.user_id = u.id
WHERE up.user_id IS NULL
ORDER BY u.created_at DESC
LIMIT 300;

-- D2) username فارغ (RLS إشعارات)
SELECT user_id, email, phone, account_type
FROM public.users_profiles
WHERE username IS NULL OR trim(username::text) = ''
LIMIT 300;

-- D3) account_type أو role فارغان (واجهة صلاحيات/أزرار)
SELECT user_id, username, account_type, role, status
FROM public.users_profiles
WHERE account_type IS NULL
   OR trim(account_type::text) = ''
   OR role IS NULL
LIMIT 300;

-- D4) in_app_notifications: username بدون user_id
SELECT id, username, user_id, type, created_at
FROM public.in_app_notifications
WHERE username IS NOT NULL
  AND trim(username::text) <> ''
  AND user_id IS NULL
ORDER BY created_at DESC
LIMIT 300;

-- D5) marketer_profiles بلا users_profiles
SELECT mp.user_id
FROM public.marketer_profiles mp
LEFT JOIN public.users_profiles up ON up.user_id = mp.user_id
WHERE up.user_id IS NULL
LIMIT 200;


-- ═══════════════════════════════════════════════════════════════════════════
-- E) عقارات: قديمة أو ناقصة تعبئة (عرض/فلتر التطبيق)
-- ═══════════════════════════════════════════════════════════════════════════

-- E1) مالك غير موجود في users_profiles
SELECT p.id, p.owner_id, p.status, p.title, p.created_at
FROM public.properties p
LEFT JOIN public.users_profiles up ON up.user_id = p.owner_id
WHERE up.user_id IS NULL
LIMIT 300;

-- E2) status فارغ أو غير معروف للتطبيق (المرئي: published, active, available, live, reserved, approved)
SELECT p.id, p.owner_id, p.status, p.workflow_stage, p.title
FROM public.properties p
WHERE p.status IS NULL
   OR trim(p.status::text) = ''
   OR lower(trim(p.status::text)) NOT IN (
        'published', 'active', 'available', 'live', 'reserved', 'approved',
        'draft', 'pending', 'inactive', 'sold', 'rented', 'deleted', 'cancelled'
      )
LIMIT 300;

-- E3) workflow_stage = published لكن status ليس من حالات العرض العام (تناقض)
SELECT p.id, p.status, p.workflow_stage, p.title
FROM public.properties p
WHERE lower(trim(coalesce(p.workflow_stage::text, ''))) = 'published'
  AND lower(trim(coalesce(p.status::text, ''))) NOT IN (
        'published', 'active', 'available', 'live', 'reserved', 'approved'
      )
LIMIT 300;

-- E4) منشور للجمهور (حسب status) بلا صور
SELECT p.id, p.owner_id, p.status, p.title, p.created_at
FROM public.properties p
WHERE lower(trim(coalesce(p.status::text, ''))) IN (
        'published', 'active', 'available', 'live', 'reserved', 'approved'
      )
  AND NOT EXISTS (
        SELECT 1 FROM public.property_images pi WHERE pi.property_id = p.id
      )
LIMIT 300;

-- E5) request_id يشير لطلب غير موجود
SELECT p.id AS property_id, p.request_id, p.status
FROM public.properties p
LEFT JOIN public.listing_requests lr ON lr.id = p.request_id
WHERE p.request_id IS NOT NULL
  AND lr.id IS NULL
LIMIT 200;

-- E6) صور يتيمة
SELECT pi.id, pi.property_id, pi.path
FROM public.property_images pi
LEFT JOIN public.properties p ON p.id = pi.property_id
WHERE p.id IS NULL
LIMIT 200;


-- ═══════════════════════════════════════════════════════════════════════════
-- F) تسويق: طلبات، عقود، عروض، تصاريح
-- ═══════════════════════════════════════════════════════════════════════════

-- F1) طلب بمالك غير موجود في users_profiles
SELECT lr.id, lr.owner_id, lr.status, lr.workflow_stage
FROM public.listing_requests lr
LEFT JOIN public.users_profiles up ON up.user_id = lr.owner_id
WHERE up.user_id IS NULL
LIMIT 300;

-- F2) عقد موقّع وعرض غير متطابق / NULL
SELECT c.id, c.request_id, c.offer_id, r.selected_offer_id, c.status::text
FROM public.listing_contracts c
JOIN public.listing_requests r ON r.id = c.request_id
WHERE lower(trim(c.status::text)) = 'signed'
  AND (
    c.offer_id IS NULL
    OR c.offer_id IS DISTINCT FROM r.selected_offer_id
  )
LIMIT 300;

-- F3) طلب يشير لعقد محذوف
SELECT lr.id, lr.contract_id
FROM public.listing_requests lr
LEFT JOIN public.listing_contracts c ON c.id = lr.contract_id
WHERE lr.contract_id IS NOT NULL
  AND c.id IS NULL
LIMIT 200;

-- F4) عروض يتيمة
SELECT o.id, o.request_id, o.status::text
FROM public.listing_offers o
LEFT JOIN public.listing_requests lr ON lr.id = o.request_id
WHERE lr.id IS NULL
LIMIT 200;

-- F5) دعوات يتيمة
SELECT inv.id, inv.request_id, inv.marketer_id
FROM public.listing_request_invites inv
LEFT JOIN public.listing_requests lr ON lr.id = inv.request_id
WHERE lr.id IS NULL
LIMIT 200;

-- F6) تصاريح بدون طلب (إن وُجد الجدول)
SELECT lp.id, lp.request_id
FROM public.listing_permits lp
LEFT JOIN public.listing_requests lr ON lr.id = lp.request_id
WHERE lr.id IS NULL
LIMIT 200;

-- F7) رسائل عقد بدون عقد
SELECT m.id, m.contract_id
FROM public.listing_contract_messages m
LEFT JOIN public.listing_contracts c ON c.id = m.contract_id
WHERE c.id IS NULL
LIMIT 200;

-- F8) عروض وصلت لكن workflow_stage قديم (مثل 20260404)
SELECT lr.id, lr.status, lr.workflow_stage, lr.updated_at
FROM public.listing_requests lr
WHERE lower(trim(coalesce(lr.status::text, ''))) = 'offers_received'
  AND lower(trim(coalesce(lr.workflow_stage::text, ''))) IN ('waiting_marketers', '')
LIMIT 300;


-- ═══════════════════════════════════════════════════════════════════════════
-- G) حجوزات، محادثات، منشآت
-- ═══════════════════════════════════════════════════════════════════════════

SELECT r.id, r.user_id, r.property_id, r.status::text
FROM public.reservations r
LEFT JOIN public.properties p ON p.id = r.property_id
LEFT JOIN public.users_profiles up ON up.user_id = r.user_id
WHERE p.id IS NULL OR up.user_id IS NULL
LIMIT 200;

SELECT c.id, c.property_id
FROM public.conversations c
LEFT JOIN public.properties p ON p.id = c.property_id
WHERE c.property_id IS NOT NULL
  AND p.id IS NULL
LIMIT 100;

SELECT m.org_id, m.user_id
FROM public.org_memberships m
LEFT JOIN public.users_profiles up ON up.user_id = m.user_id
WHERE up.user_id IS NULL
LIMIT 200;


-- ═══════════════════════════════════════════════════════════════════════════
-- H) وظائف RPC مرجعية (توسيع القائمة حسب استدعاءاتك)
-- ═══════════════════════════════════════════════════════════════════════════
SELECT p.proname AS function_name
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'reserve_property',
    'release_or_expire_reservation',
    'cancel_reservation',
    'expire_reservations',
    'reservations_pricing_guard',
    'cron_expire_reservations',
    'publish_property_from_contract',
    'create_listing_contract_from_offer',
    'ensure_my_org_unit',
    'my_org_context',
    'org_effective_seat_limit',
    'ack_profile_data_revision',
    'accept_terms_v1',
    'register_user_device_v2',
    'record_property_listing_view',
    'signup_username_taken',
    'signup_phone_taken',
    'app_rls_my_profile_username',
    'app_rls_users_profile_select_allowed'
  )
ORDER BY p.proname;

-- =============================================================================
-- ملخص الاستخدام:
--   • أي صف في القسم A = نفّذ migration لإضافة العمود/الجدول.
--   • B/C = مراجعة أمنية يدوية؛ لا تعبئة تلقائية.
--   • D–G = بيانات للتصحيح اليدوي أو سكربت UPDATE/INSERT بعد مراجعة كل صف.
--   • H = إن نقصت دالة، طبّق الملف SQL المناسب من supabase/sql.
-- =============================================================================
