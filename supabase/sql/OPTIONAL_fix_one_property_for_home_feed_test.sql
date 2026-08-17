-- ⚠️ للتجربة فقط — يُظهر إعلاناً واحداً في الرئيسية (ضيف + تطبيق)
-- إن بقي anon = 0: نفّذ APPLY_NOW_force_one_property_visible_anon.sql
-- ثم diagnostics_why_anon_still_zero_after_update.sql

SELECT count(*)::bigint AS not_deleted_before
FROM public.properties
WHERE status IS DISTINCT FROM 'deleted';

UPDATE public.properties p
SET
  status = 'published',
  workflow_stage = 'published',
  home_feed_suppressed = false
WHERE p.id = (
  SELECT id
  FROM public.properties
  WHERE status IS DISTINCT FROM 'deleted'
  ORDER BY created_at DESC NULLS LAST
  LIMIT 1
)
RETURNING id, status, workflow_stage, home_feed_suppressed;

-- تحقق
SELECT count(*)::bigint AS superuser_matches_policy_logic
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
  AND COALESCE(p.home_feed_suppressed, false) = false
  AND (
    p.status IN (
      'published', 'active', 'available', 'live', 'reserved', 'approved',
      'listed', 'open', 'visible', 'for_sale', 'for_rent', 'forsale', 'forrent'
    )
    OR (
      p.status = 'draft'
      AND p.workflow_stage IN (
        'waiting_marketers', 'marketer_selected', 'contract_pending',
        'contract_sent', 'contract_returned', 'contract_signed',
        'permit_pending', 'permit_issued', 'published', 'reserved', 'inactive_72h'
      )
    )
  );

SET ROLE anon;
SELECT count(*)::bigint AS properties_visible_as_anon FROM public.properties;
RESET ROLE;
