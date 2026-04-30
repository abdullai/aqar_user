-- مواءمة قيد عمود status مع حالات القراءة العامة في RLS (مثل 20260459) + مسودة/مغلق.
-- نفّذ في Supabase SQL Editor بعد مراجعة القيم الموجودة فعلياً في الجدول.
-- إن كان اسم القيد مختلفاً عندك، عدّل سطر DROP أو استخدم:
--   SELECT conname FROM pg_constraint WHERE conrelid = 'public.market_property_requests'::regclass;

ALTER TABLE public.market_property_requests
  DROP CONSTRAINT IF EXISTS market_property_requests_status_check;

ALTER TABLE public.market_property_requests
  ADD CONSTRAINT market_property_requests_status_check
  CHECK (status = ANY (ARRAY[
    'draft',
    'published',
    'closed',
    'deleted',
    'active',
    'live',
    'open',
    'visible',
    'under_review',
    'in_progress',
    'seeking',
    'bidding',
    'negotiating',
    'collecting_offers'
  ]::text[]));

COMMENT ON CONSTRAINT market_property_requests_status_check
  ON public.market_property_requests IS
  'حالات دورة حياة الطلب — متوافقة مع سياسة SELECT العامة (20260459) والتطبيق.';
