-- =============================================================================
-- توحيد سياسات الرئيسية على properties
--
-- الوضع الحالي (من التشخيص):
--   • properties_public_home_select      → واسعة جداً (محذوف + suppressed فقط)
--   • properties_public_home_select_old  → صارمة (مسوّق + REGA + وسائط…)
--
-- مع PERMISSIVE: أي سياسة تكفي (OR) — الواسعة تُظهر كل ما ليس محذوفاً/مكتوماً
--   (_old لا تضيف صفوفاً). الواسعة ناقصة أمنياً (تُظهر مسودات مبكرة).
--
-- هذا السكربت:
--   1) يحذف السياستين
--   2) يُنشئ سياسة واحدة = فلتر التطبيق (20260461) + forsale/forrent
--   3) يُبقي property_images متوافقة (نفس منطق v4)
--
-- نفّذ بعد: APPLY_NOW_v4_property_images_anon_rest.sql
-- =============================================================================

BEGIN;

GRANT SELECT ON public.properties TO anon, authenticated;

DROP POLICY IF EXISTS "properties_public_home_select" ON public.properties;
DROP POLICY IF EXISTS "properties_public_home_select_old" ON public.properties;
DROP POLICY IF EXISTS "properties_public_read_published_like" ON public.properties;

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
          'waiting_marketers',
          'marketer_selected',
          'contract_pending',
          'contract_sent',
          'contract_returned',
          'contract_signed',
          'permit_pending',
          'permit_issued',
          'published',
          'reserved',
          'inactive_72h'
        )
      )
    )
  );

COMMENT ON POLICY "properties_public_home_select" ON public.properties IS
  'رئيسية عامة — فلتر التطبيق (20260461). لا تكرار مع _old أو publish_ready الصارم.';

COMMIT;

-- تحقق
SELECT policyname, permissive, left(qual::text, 120) AS using_preview
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'properties'
  AND cmd = 'SELECT'
  AND 'anon' = ANY (roles)
ORDER BY policyname;

SELECT count(*)::bigint AS properties_matching_home_select_policy
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
