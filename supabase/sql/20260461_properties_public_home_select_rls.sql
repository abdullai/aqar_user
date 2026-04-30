-- تأكد من صلاحية القراءة لدور API (عادةً ممنوحة مسبقاً في Supabase).
GRANT SELECT ON public.properties TO anon, authenticated;

-- =============================================================================
-- قراءة عامة لجدول properties للرئيسية (ضيف + مستخدم) — يطابق منطق التطبيق:
--   lib/shared/core/supabase_schema_selects.dart → propertiesHomeFeedOrFilter
-- بدون سياسة SELECT لدور anon تبقى استجابة PostgREST للضيف فارغة رغم أن SQL
-- كمشرف يعرض 21 صفاً.
--
-- نفّذ في Supabase → SQL Editor بعد مراجعة عدم تكرار اسم السياسة مع سياساتكم.
-- =============================================================================

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
      'listed', 'open', 'visible', 'for_sale', 'for_rent'
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
  'قراءة الرئيسية للضيف/المسجّل — نفس فلتر التطبيق (مع سياسات المالك/المسوّق الأخرى).';

-- إن وُجدت سياسة قديمة `properties_public_read_published_like` (ضيّقة أو RESTRICTIVE)
-- واختفت المسودات الحيّة من API: نفّذ `20260462_properties_drop_redundant_public_read_policy.sql`.
