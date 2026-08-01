-- =============================================================================
-- تشخيص طلبات التسويق للمستخدم username = 100000000 (ومرادفه 1000000000)
-- نفّذ في Supabase SQL Editor
-- =============================================================================

-- 1) هوية المستخدم
SELECT user_id, username, account_type, verified_at
FROM public.users_profiles
WHERE username IN ('100000000', '1000000000')
   OR username LIKE '100000000%';

-- 2) كل طلبات التسويق لهذا المستخدم (كمالك للطلب owner_id)
WITH u AS (
  SELECT user_id
  FROM public.users_profiles
  WHERE username IN ('100000000', '1000000000')
)
SELECT
  lr.id,
  lr.public_code,
  lr.title,
  lr.city,
  lr.status,
  lr.workflow_stage,
  lr.selected_marketer_id,
  lr.marketing_round,
  lr.preview_property_id,
  lr.created_at,
  lr.updated_at,
  lr.waiting_marketers_since,
  -- هل يبدو مسار «بدون تصريح / سوق»؟
  coalesce(
    (lr.payload_json::jsonb ->> 'no_rega_ad_license')::boolean,
    false
  ) AS no_rega_ad_license,
  coalesce(
    (lr.payload_json::jsonb ->> 'market_without_rega_license')::boolean,
    false
  ) AS market_without_rega_license,
  coalesce(
    (lr.payload_json::jsonb ->> 'market_consent')::boolean,
    false
  ) AS market_consent,
  left(coalesce(lr.payload_json::text, ''), 200) AS payload_preview
FROM public.listing_requests lr
JOIN u ON u.user_id = lr.owner_id
ORDER BY lr.created_at DESC;

-- 3) الطلبات المفتوحة فقط (بانتظار مسوّقين) — ما يفترض ظهوره في السوق للآخرين
WITH u AS (
  SELECT user_id
  FROM public.users_profiles
  WHERE username IN ('100000000', '1000000000')
)
SELECT
  lr.id,
  lr.title,
  lr.workflow_stage,
  lr.status,
  lr.selected_marketer_id,
  lr.created_at,
  CASE
    WHEN lower(trim(coalesce(lr.workflow_stage, ''))) = 'waiting_marketers'
         AND lr.selected_marketer_id IS NULL
      THEN 'SHOULD_APPEAR_IN_OPEN_MARKET_FOR_OTHERS'
    ELSE 'NOT_OPEN_MARKET'
  END AS market_visibility
FROM public.listing_requests lr
JOIN u ON u.user_id = lr.owner_id
WHERE lower(trim(coalesce(lr.workflow_stage, ''))) IN (
        'waiting_marketers', 'pending', 'draft'
      )
   OR lr.selected_marketer_id IS NULL
ORDER BY lr.created_at DESC;

-- 4) عقارات مرتبطة (معاينة / request_id) — هل نُشرت بالخطأ في الرئيسية؟
WITH u AS (
  SELECT user_id
  FROM public.users_profiles
  WHERE username IN ('100000000', '1000000000')
)
SELECT
  p.id AS property_id,
  p.request_id,
  p.title,
  p.status,
  p.workflow_stage,
  p.home_feed_suppressed,
  p.published_by_marketer_id,
  p.owner_id,
  p.created_at
FROM public.properties p
JOIN u ON u.user_id = p.owner_id
   OR u.user_id = p.published_by_marketer_id
ORDER BY p.created_at DESC
LIMIT 50;

-- 5) دعوات/عروض على طلبات هذا المستخدم
WITH u AS (
  SELECT user_id
  FROM public.users_profiles
  WHERE username IN ('100000000', '1000000000')
),
reqs AS (
  SELECT lr.id
  FROM public.listing_requests lr
  JOIN u ON u.user_id = lr.owner_id
)
SELECT 'invite' AS kind, inv.id, inv.request_id, inv.marketer_id, inv.status, inv.created_at
FROM public.listing_request_invites inv
JOIN reqs r ON r.id = inv.request_id
UNION ALL
SELECT 'offer', o.id, o.request_id, o.marketer_id, o.status::text, o.created_at
FROM public.listing_offers o
JOIN reqs r ON r.id = o.request_id
ORDER BY created_at DESC;
