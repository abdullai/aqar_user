-- =============================================================================
-- إعلان واحد ظاهر لـ anon — يعمل حتى لو كل الصفوف deleted أو الحالات غريبة
--
-- نفّذ diagnostics_why_anon_still_zero_after_update.sql أولاً إن فشل هذا.
-- =============================================================================

BEGIN;

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.properties TO anon, authenticated;

-- تأكد من سياسة الرئيسية (إعادة إنشاء آمنة)
DROP POLICY IF EXISTS "properties_public_home_select" ON public.properties;

CREATE POLICY "properties_public_home_select"
  ON public.properties
  FOR SELECT
  TO anon, authenticated
  USING (
    status IS DISTINCT FROM 'deleted'
    AND COALESCE(home_feed_suppressed, false) = false
    AND (
      status IN (
        'published', 'active', 'available', 'live', 'reserved', 'approved',
        'listed', 'open', 'visible', 'for_sale', 'for_rent', 'forsale', 'forrent'
      )
      OR (
        status = 'draft'
        AND workflow_stage IN (
          'waiting_marketers', 'marketer_selected', 'contract_pending',
          'contract_sent', 'contract_returned', 'contract_signed',
          'permit_pending', 'permit_issued', 'published', 'reserved', 'inactive_72h'
        )
      )
    )
  );

-- إن وُجدت سياسة RESTRICTIVE باسم شائع تمنع الضيف — احذفها (عدّل الاسم إن ظهر في التشخيص)
DROP POLICY IF EXISTS "properties_deny_anon_select" ON public.properties;
DROP POLICY IF EXISTS "properties_hide_from_anon" ON public.properties;
DROP POLICY IF EXISTS "properties_authenticated_only" ON public.properties;

-- 1) إن وُجد غير محذوف: حدّث الأحدث
WITH target AS (
  SELECT id
  FROM public.properties
  WHERE status IS DISTINCT FROM 'deleted'
  ORDER BY created_at DESC NULLS LAST
  LIMIT 1
)
UPDATE public.properties p
SET
  status = 'published',
  workflow_stage = 'published',
  home_feed_suppressed = false
FROM target t
WHERE p.id = t.id
RETURNING p.id, p.status, p.workflow_stage, 'updated_existing' AS action;

-- 2) إن لا يوجد أي صف غير محذوف: أعد تفعيل أحدث محذوف للتجربة فقط
UPDATE public.properties p
SET
  status = 'published',
  workflow_stage = 'published',
  home_feed_suppressed = false
WHERE p.id = (
  SELECT id FROM public.properties ORDER BY created_at DESC NULLS LAST LIMIT 1
)
  AND NOT EXISTS (
    SELECT 1 FROM public.properties WHERE status IS DISTINCT FROM 'deleted'
  )
RETURNING p.id, p.status, p.workflow_stage, 'revived_deleted_row_for_test' AS action;

COMMIT;

-- تحقق (شغّل الأقسام واحداً واحداً)
SELECT count(*)::bigint AS not_deleted FROM public.properties
WHERE status IS DISTINCT FROM 'deleted';

SELECT count(*)::bigint AS superuser_matches FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
  AND COALESCE(p.home_feed_suppressed, false) = false
  AND p.status IN (
    'published','active','available','live','reserved','approved',
    'listed','open','visible','for_sale','for_rent','forsale','forrent'
  );

-- إن postgres_can_set_anon = false من التشخيص (G)، نفّذ مرة واحدة كمشرف:
-- GRANT anon TO postgres;

SET ROLE anon;
SELECT count(*)::bigint AS properties_visible_as_anon FROM public.properties;
RESET ROLE;
