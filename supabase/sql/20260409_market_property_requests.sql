-- طلبات عقارية تظهر في الرئيسية (شريط واحد مع الإعلانات) — RLS للقراءة العامة عند النشر.
-- نفّذ في Supabase → SQL Editor ثم حدّث سياساتك إن لزم.

CREATE TABLE IF NOT EXISTS public.market_property_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  requester_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'published'
    CHECK (status IN ('draft', 'published', 'closed')),
  title text NOT NULL,
  description text,
  purpose text NOT NULL CHECK (purpose IN ('purchase', 'rent')),
  property_type text NOT NULL,
  city text NOT NULL,
  districts jsonb NOT NULL DEFAULT '[]'::jsonb,
  budget_min numeric,
  budget_max numeric,
  area_min_m2 numeric,
  prefer_new boolean NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_market_property_requests_published_created
  ON public.market_property_requests (status, created_at DESC);

ALTER TABLE public.market_property_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS market_property_requests_public_select_published
  ON public.market_property_requests;
CREATE POLICY market_property_requests_public_select_published
  ON public.market_property_requests
  FOR SELECT
  TO anon, authenticated
  USING (status = 'published');

DROP POLICY IF EXISTS market_property_requests_insert_own
  ON public.market_property_requests;
CREATE POLICY market_property_requests_insert_own
  ON public.market_property_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (requester_id = auth.uid());

DROP POLICY IF EXISTS market_property_requests_update_own
  ON public.market_property_requests;
CREATE POLICY market_property_requests_update_own
  ON public.market_property_requests
  FOR UPDATE
  TO authenticated
  USING (requester_id = auth.uid())
  WITH CHECK (requester_id = auth.uid());

DROP POLICY IF EXISTS market_property_requests_delete_own
  ON public.market_property_requests;
CREATE POLICY market_property_requests_delete_own
  ON public.market_property_requests
  FOR DELETE
  TO authenticated
  USING (requester_id = auth.uid());

COMMENT ON TABLE public.market_property_requests IS
  'طلبات شراء/إيجار تظهر في الرئيسية بجانب الإعلانات؛ التطبيق يفلترها بتبويب علوي.';
