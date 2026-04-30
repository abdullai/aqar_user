-- =============================================================================
-- طلبات السوق: حقل JSON اختياري لتفاصيل إضافية (مدة الإيجار، غرف، مرافق…)
-- نفّذ في Supabase → SQL Editor بعد 20260409_market_property_requests.sql
-- =============================================================================

BEGIN;

ALTER TABLE public.market_property_requests
  ADD COLUMN IF NOT EXISTS details_json jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.market_property_requests.details_json IS
  'تفاصيل من التطبيق: rent_term، bedrooms، bathrooms، amenities، إلخ.';

COMMIT;
