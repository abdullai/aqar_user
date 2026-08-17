-- properties_visible_as_anon = 0 رغم سياسة 20260461 — نفّذ كل قسم لوحده

-- (1) كمشرف: هل يوجد أي صف يطابق نص السياسة؟
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

-- (2) إجمالي غير المحذوف
SELECT count(*)::bigint AS not_deleted FROM public.properties
WHERE status IS DISTINCT FROM 'deleted';

-- (3) status — ما القيم الفعلية؟ (حساس لحالة الأحرف: Published ≠ published)
SELECT coalesce(status::text, '<null>') AS status, count(*)::bigint AS n
FROM public.properties
WHERE status IS DISTINCT FROM 'deleted'
GROUP BY 1
ORDER BY n DESC;

-- (3b) هل تطابق بلا حساسية لحالة الأحرف؟
SELECT count(*)::bigint AS would_match_if_lower_status
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
  AND COALESCE(p.home_feed_suppressed, false) = false
  AND (
    lower(coalesce(p.status::text, '')) IN (
      'published', 'active', 'available', 'live', 'reserved', 'approved',
      'listed', 'open', 'visible', 'for_sale', 'for_rent', 'forsale', 'forrent'
    )
    OR (
      lower(coalesce(p.status::text, '')) = 'draft'
      AND lower(coalesce(p.workflow_stage::text, '')) IN (
        'waiting_marketers', 'marketer_selected', 'contract_pending',
        'contract_sent', 'contract_returned', 'contract_signed',
        'permit_pending', 'permit_issued', 'published', 'reserved', 'inactive_72h'
      )
    )
  );

-- (4) workflow_stage للمسودات
SELECT coalesce(workflow_stage::text, '<null>') AS stage, count(*)::bigint AS n
FROM public.properties
WHERE status = 'draft'
GROUP BY 1
ORDER BY n DESC;

-- (5) home_feed_suppressed
SELECT COALESCE(home_feed_suppressed, false) AS suppressed, count(*)::bigint AS n
FROM public.properties
WHERE status IS DISTINCT FROM 'deleted'
GROUP BY 1;

-- (6) سياسات RESTRICTIVE على properties (قد تحجب anon بالكامل)
SELECT policyname, permissive, roles::text, cmd, qual::text
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'properties'
  AND permissive = 'RESTRICTIVE'
ORDER BY policyname;

-- (7) كل سياسات SELECT لـ anon
SELECT policyname, permissive, roles::text, left(qual::text, 100) AS using_preview
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'properties'
  AND cmd IN ('SELECT', 'ALL')
  AND ('anon' = ANY (roles) OR roles IS NULL)
ORDER BY permissive, policyname;

-- (8) anon count
SET ROLE anon;
SELECT count(*)::bigint AS properties_visible_as_anon FROM public.properties;
RESET ROLE;

-- (9) عينة: أقرب 10 صفوف للظهور (غيّر status/workflow يدوياً إن لزم)
SELECT id, status, workflow_stage, home_feed_suppressed,
       created_at
FROM public.properties
WHERE status IS DISTINCT FROM 'deleted'
ORDER BY created_at DESC NULLS LAST
LIMIT 10;
