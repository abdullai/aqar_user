-- نفّذ هذا الملف مرة واحدة — صف واحد بكل الأرقام (لا تعتمد على آخر SELECT فقط)

SELECT
  (SELECT count(*)::bigint FROM public.properties) AS total_rows,
  (SELECT count(*)::bigint FROM public.properties
   WHERE coalesce(status::text, '') IS DISTINCT FROM 'deleted') AS rows_not_deleted,
  (SELECT c.relkind FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'properties') AS relkind_r_is_table_v_is_view,
  (SELECT c.relrowsecurity FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'properties') AS rls_enabled,
  (SELECT count(*)::bigint FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'properties'
     AND permissive = 'RESTRICTIVE') AS restrictive_policy_count,
  (SELECT count(*)::bigint FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'properties'
     AND cmd IN ('SELECT', 'ALL')
     AND 'anon' = ANY (roles)) AS anon_select_policy_count,
  EXISTS (
    SELECT 1 FROM information_schema.role_table_grants g
    WHERE g.table_schema = 'public' AND g.table_name = 'properties'
      AND g.grantee = 'anon' AND g.privilege_type = 'SELECT'
  ) AS anon_has_grant_select,
  (SELECT count(*)::bigint FROM public.properties) AS superuser_count_same_moment;

-- ثم (منفصل): عدّ كـ anon بعد سياسة USING (true)
SET ROLE anon;
SELECT
  current_user AS role_while_anon,
  (SELECT count(*)::bigint FROM public.properties) AS anon_count;
RESET ROLE;
