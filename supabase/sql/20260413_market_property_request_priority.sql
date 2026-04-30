-- درجة إلحاح طلب السوق (مرن → طلب فوري). نفّذ في Supabase SQL Editor إن لم يكن العمود موجوداً.

ALTER TABLE public.market_property_requests
  ADD COLUMN IF NOT EXISTS request_priority text NOT NULL DEFAULT 'standard'
  CHECK (
    request_priority IN (
      'flexible',
      'standard',
      'priority',
      'urgent',
      'immediate'
    )
  );

COMMENT ON COLUMN public.market_property_requests.request_priority IS
  'Urgency tier for market property requests (home feed ordering + UI badge).';

CREATE INDEX IF NOT EXISTS idx_market_property_requests_priority_created
  ON public.market_property_requests (request_priority, created_at DESC);
