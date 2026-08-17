-- توسيع قائمة حالات العقارات/الطلبات المعروضة في الرئيسية (PostgREST + RLS + التطبيق).
-- نفّذ في Supabase → SQL Editor بعد مراجعة عدم تعارض أسماء السياسات.
-- يطابق: lib/shared/core/supabase_schema_selects.dart

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
      'listed', 'open', 'visible', 'for_sale', 'for_rent',
      'forsale', 'forrent',
      'pending', 'under_review', 'in_review', 'review', 'processing', 'ready', 'verified'
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
  'قراءة الرئيسية — موسّع ليشمل حالات legacy شائعة (pending / under_review / forsale…).';
