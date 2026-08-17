-- بعد OPTIONAL_fix_one_property… وما زال anon = 0 — نفّذ كل قسم لوحده

-- (A) هل يوجد إعلان غير محذوف أصلاً؟
SELECT count(*)::bigint AS not_deleted FROM public.properties
WHERE status IS DISTINCT FROM 'deleted';

-- (B) آخر إعلان غير محذوف — هل يطابق السياسة؟
SELECT
  p.id,
  p.status,
  p.workflow_stage,
  COALESCE(p.home_feed_suppressed, false) AS suppressed,
  (p.status IN (
    'published','active','available','live','reserved','approved',
    'listed','open','visible','for_sale','for_rent','forsale','forrent'
  )) AS status_in_list,
  public.property_id_public_home_feed_visible(p.id) AS home_visible_fn
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
ORDER BY p.created_at DESC NULLS LAST
LIMIT 5;

-- (C) كمشرف: عدد يطابق منطق السياسة
SELECT count(*)::bigint AS superuser_matches_policy_logic
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
  AND COALESCE(p.home_feed_suppressed, false) = false
  AND (
    p.status IN (
      'published','active','available','live','reserved','approved',
      'listed','open','visible','for_sale','for_rent','forsale','forrent'
    )
    OR (
      p.status = 'draft'
      AND p.workflow_stage IN (
        'waiting_marketers','marketer_selected','contract_pending',
        'contract_sent','contract_returned','contract_signed',
        'permit_pending','permit_issued','published','reserved','inactive_72h'
      )
    )
  );

-- (D) كل سياسات properties (PERMISSIVE + RESTRICTIVE)
SELECT tablename, policyname, permissive, roles::text, cmd,
       left(qual::text, 150) AS using_preview
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'properties'
ORDER BY permissive, policyname;

-- (E) RESTRICTIVE فقط — إن وُجدت قد تُصفّر anon بالكامل
SELECT policyname, qual::text
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'properties'
  AND permissive = 'RESTRICTIVE';

-- (F) GRANT SELECT لـ anon على الجدول؟
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'properties'
  AND grantee IN ('anon', 'authenticated');

-- (G) هل يمكن لـ postgres استخدام دور anon؟ (إن فشل SET ROLE)
SELECT pg_has_role('postgres', 'anon', 'USAGE') AS postgres_can_set_anon;

-- (H) عدّ كـ anon
SET ROLE anon;
SELECT current_user, session_user;
SELECT count(*)::bigint AS properties_visible_as_anon FROM public.properties;
RESET ROLE;

-- (I) دالة تحقق عبر SECURITY INVOKER (تقييم RLS كالمستدعي)
CREATE OR REPLACE FUNCTION public.debug_properties_count_for_caller()
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT count(*)::bigint FROM public.properties;
$$;

REVOKE ALL ON FUNCTION public.debug_properties_count_for_caller() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.debug_properties_count_for_caller() TO anon, authenticated, service_role;

SELECT public.debug_properties_count_for_caller() AS count_as_definer_session;

SET ROLE anon;
SELECT public.debug_properties_count_for_caller() AS count_via_fn_as_anon;
RESET ROLE;
