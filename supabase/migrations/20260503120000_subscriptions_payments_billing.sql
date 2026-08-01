-- Subscriptions, saved payment tokens (mock/real gateway), and billing ledger.
-- organization_id references public.org_units (project naming: "organization" = org unit).

-- ---------------------------------------------------------------------------
-- 1) Plans
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.subscription_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name_ar text NOT NULL,
  name_en text NOT NULL,
  description_ar text,
  description_en text,
  user_type text NOT NULL,
  price_monthly numeric(10,2) NOT NULL,
  price_yearly numeric(10,2) NOT NULL,
  max_members int,
  max_properties int,
  max_ads_per_month int,
  max_listing_requests int,
  has_fal_license boolean NOT NULL DEFAULT true,
  has_analytics boolean NOT NULL DEFAULT false,
  has_api_access boolean NOT NULL DEFAULT false,
  has_priority_support boolean NOT NULL DEFAULT false,
  features jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_subscription_plans_user_type_active
  ON public.subscription_plans (user_type, is_active, sort_order);

-- ---------------------------------------------------------------------------
-- 2) User / org subscriptions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  organization_id uuid REFERENCES public.org_units (id) ON DELETE SET NULL,
  plan_id uuid NOT NULL REFERENCES public.subscription_plans (id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('active', 'expired', 'cancelled', 'pending')),
  period text NOT NULL DEFAULT 'monthly'
    CHECK (period IN ('monthly', 'yearly')),
  start_date date NOT NULL,
  end_date date NOT NULL,
  auto_renew boolean NOT NULL DEFAULT true,
  max_members_override int,
  cancelled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user
  ON public.user_subscriptions (user_id, status, end_date DESC);

CREATE INDEX IF NOT EXISTS idx_user_subscriptions_org
  ON public.user_subscriptions (organization_id);

-- ---------------------------------------------------------------------------
-- 3) Saved cards (tokens only — never full PAN)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.saved_cards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  card_token text NOT NULL,
  card_bin varchar(6),
  last_four varchar(4) NOT NULL,
  card_scheme varchar(20) NOT NULL,
  card_holder_name text,
  expiry_month int NOT NULL,
  expiry_year int NOT NULL,
  label text,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT saved_cards_token_user_unique UNIQUE (user_id, card_token)
);

CREATE INDEX IF NOT EXISTS idx_saved_cards_user
  ON public.saved_cards (user_id, is_default DESC, created_at DESC);

-- ---------------------------------------------------------------------------
-- 4) Billing ledger (named billing_transactions to avoid generic collisions)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.billing_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  subscription_id uuid REFERENCES public.user_subscriptions (id) ON DELETE SET NULL,
  amount numeric(10,2) NOT NULL,
  currency text NOT NULL DEFAULT 'SAR',
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'success', 'failed', 'refunded')),
  payment_method text,
  card_id uuid REFERENCES public.saved_cards (id) ON DELETE SET NULL,
  gateway_transaction_id text,
  gateway_response jsonb,
  invoice_url text,
  receipt_sent boolean NOT NULL DEFAULT false,
  title_ar text,
  title_en text,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_billing_transactions_user_created
  ON public.billing_transactions (user_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 5) Extra seats purchase queue (optional; complements org RPC flows)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.extra_seats_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.org_units (id) ON DELETE CASCADE,
  seats_requested int NOT NULL CHECK (seats_requested > 0),
  amount numeric(10,2) NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  transaction_id uuid REFERENCES public.billing_transactions (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_extra_seats_requests_org
  ON public.extra_seats_requests (organization_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- updated_at trigger (reuse pattern if exists — lightweight inline)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.touch_user_subscriptions_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_user_subscriptions_touch ON public.user_subscriptions;
CREATE TRIGGER tr_user_subscriptions_touch
  BEFORE UPDATE ON public.user_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.touch_user_subscriptions_updated_at();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.extra_seats_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subscription_plans_select_active ON public.subscription_plans;
CREATE POLICY subscription_plans_select_active ON public.subscription_plans
  FOR SELECT TO authenticated, anon
  USING (is_active = true);

DROP POLICY IF EXISTS user_subscriptions_select_own ON public.user_subscriptions;
CREATE POLICY user_subscriptions_select_own ON public.user_subscriptions
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR (
      organization_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.org_units o
        WHERE o.id = organization_id AND o.owner_user_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS user_subscriptions_insert_own ON public.user_subscriptions;
CREATE POLICY user_subscriptions_insert_own ON public.user_subscriptions
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS user_subscriptions_update_own ON public.user_subscriptions;
CREATE POLICY user_subscriptions_update_own ON public.user_subscriptions
  FOR UPDATE TO authenticated
  USING (
    user_id = auth.uid()
    OR (
      organization_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.org_units o
        WHERE o.id = organization_id AND o.owner_user_id = auth.uid()
      )
    )
  )
  WITH CHECK (
    user_id = auth.uid()
    OR (
      organization_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.org_units o
        WHERE o.id = organization_id AND o.owner_user_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS saved_cards_all_own ON public.saved_cards;
CREATE POLICY saved_cards_all_own ON public.saved_cards
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS billing_transactions_select_own ON public.billing_transactions;
CREATE POLICY billing_transactions_select_own ON public.billing_transactions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS billing_transactions_insert_own ON public.billing_transactions;
CREATE POLICY billing_transactions_insert_own ON public.billing_transactions
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS billing_transactions_update_own ON public.billing_transactions;
CREATE POLICY billing_transactions_update_own ON public.billing_transactions
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS extra_seats_org_owner ON public.extra_seats_requests;
CREATE POLICY extra_seats_org_owner ON public.extra_seats_requests
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.org_units o
      WHERE o.id = organization_id AND o.owner_user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.org_units o
      WHERE o.id = organization_id AND o.owner_user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- Seed plans (idempotent by name + user_type)
-- ---------------------------------------------------------------------------
INSERT INTO public.subscription_plans (
  name_ar, name_en, user_type, price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month, max_listing_requests,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  features, sort_order
)
SELECT * FROM (VALUES
  (N'الباقة الأساسية', 'Basic', 'individual', 59.00::numeric, 566.40::numeric, 1::int, NULL::int, 50::int, 20::int,
   true, false, false, false,
   '{"support_ar":"بريد إلكتروني","support_en":"Email only","fal_badge":false}'::jsonb, 1::int),
  (N'الباقة الاحترافية', 'Professional', 'individual', 149.00::numeric, 1430.40::numeric, 1::int, NULL::int, 500::int, 200::int,
   true, true, false, true,
   '{"support_ar":"دعم 24/7","support_en":"24/7 support","fal_badge":true,"reports":true}'::jsonb, 2::int),
  (N'الباقة المؤسسية', 'Enterprise', 'individual', 499.00::numeric, 4790.40::numeric, 1::int, NULL::int, NULL::int, NULL::int,
   true, true, true, true,
   '{"support_ar":"أولوية قصوى","support_en":"Priority + dedicated","fal_badge":true,"api":true}'::jsonb, 3::int),

  (N'الباقة الأساسية', 'Basic', 'marketer', 59.00::numeric, 566.40::numeric, 3::int, NULL::int, 50::int, 20::int,
   true, false, false, false,
   '{"support_ar":"بريد إلكتروني","support_en":"Email only","fal_badge":false}'::jsonb, 1::int),
  (N'الباقة الاحترافية', 'Professional', 'marketer', 149.00::numeric, 1430.40::numeric, 10::int, NULL::int, 500::int, 200::int,
   true, true, false, true,
   '{"support_ar":"دعم 24/7","support_en":"24/7 support","fal_badge":true,"reports":true}'::jsonb, 2::int),
  (N'الباقة المؤسسية', 'Enterprise', 'marketer', 499.00::numeric, 4790.40::numeric, NULL::int, NULL::int, NULL::int, NULL::int,
   true, true, true, true,
   '{"support_ar":"أولوية قصوى","support_en":"Priority + dedicated","fal_badge":true,"api":true}'::jsonb, 3::int),

  (N'الباقة الأساسية', 'Basic', 'office', 59.00::numeric, 566.40::numeric, 3::int, NULL::int, 50::int, 20::int,
   true, false, false, false,
   '{"support_ar":"بريد إلكتروني","support_en":"Email only","fal_badge":false}'::jsonb, 1::int),
  (N'الباقة الاحترافية', 'Professional', 'office', 149.00::numeric, 1430.40::numeric, 10::int, NULL::int, 500::int, 200::int,
   true, true, false, true,
   '{"support_ar":"دعم 24/7","support_en":"24/7 support","fal_badge":true,"reports":true}'::jsonb, 2::int),
  (N'الباقة المؤسسية', 'Enterprise', 'office', 499.00::numeric, 4790.40::numeric, NULL::int, NULL::int, NULL::int, NULL::int,
   true, true, true, true,
   '{"support_ar":"أولوية قصوى","support_en":"Priority + dedicated","fal_badge":true,"api":true}'::jsonb, 3::int)
) AS v(
  name_ar, name_en, user_type, price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month, max_listing_requests,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  features, sort_order
)
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans p
  WHERE p.user_type = v.user_type AND p.name_en = v.name_en
);

COMMENT ON TABLE public.subscription_plans IS 'Commercial subscription tiers by audience (mock billing until licensed gateway).';
COMMENT ON TABLE public.saved_cards IS 'PCI-style: store gateway tokens + display metadata only.';
COMMENT ON TABLE public.billing_transactions IS 'Financial ledger rows (app naming; not SQL BEGIN/COMMIT).';
