-- Billing audit trail, promotions/trials scaffolding, staff read policies for operations.

-- ---------------------------------------------------------------------------
-- 1) Append-only audit (populated by trigger on billing_transactions)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.billing_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  action text NOT NULL,
  entity_table text NOT NULL DEFAULT 'billing_transactions',
  entity_id uuid,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_billing_audit_log_user_created
  ON public.billing_audit_log (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_billing_audit_log_entity
  ON public.billing_audit_log (entity_table, entity_id);

ALTER TABLE public.billing_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS billing_audit_log_select ON public.billing_audit_log;
CREATE POLICY billing_audit_log_select ON public.billing_audit_log
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_platform_staff(auth.uid())
  );

-- No INSERT/UPDATE/DELETE for authenticated — rows come from trigger (table owner).

CREATE OR REPLACE FUNCTION public.billing_audit_on_transaction_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND (NEW.status IS DISTINCT FROM OLD.status) THEN
    INSERT INTO public.billing_audit_log (user_id, action, entity_table, entity_id, payload)
    VALUES (
      NEW.user_id,
      'billing_transaction_' || coalesce(NEW.status, 'unknown'),
      'billing_transactions',
      NEW.id,
      jsonb_build_object(
        'old_status', OLD.status,
        'new_status', NEW.status,
        'amount', NEW.amount,
        'currency', NEW.currency,
        'payment_method', NEW.payment_method,
        'gateway_transaction_id', NEW.gateway_transaction_id,
        'subscription_id', NEW.subscription_id
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_billing_transactions_audit ON public.billing_transactions;
CREATE TRIGGER tr_billing_transactions_audit
  AFTER UPDATE ON public.billing_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.billing_audit_on_transaction_update();

-- ---------------------------------------------------------------------------
-- 2) Promotions / trials (redeem logic in app or future RPC)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.subscription_promotions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('percent_off', 'fixed_off', 'trial_days', 'first_payment_bonus')),
  value numeric(10,2) NOT NULL DEFAULT 0,
  trial_days int,
  valid_from timestamptz,
  valid_to timestamptz,
  max_redemptions int,
  per_user_limit int NOT NULL DEFAULT 1,
  applies_user_types text[],
  title_ar text,
  title_en text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_subscription_promotions_code_lower
  ON public.subscription_promotions (lower(code));

CREATE INDEX IF NOT EXISTS idx_subscription_promotions_active
  ON public.subscription_promotions (is_active, valid_from, valid_to);

CREATE TABLE IF NOT EXISTS public.subscription_promotion_redemptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  promotion_id uuid NOT NULL REFERENCES public.subscription_promotions (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  billing_transaction_id uuid REFERENCES public.billing_transactions (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_promo_redemptions_user
  ON public.subscription_promotion_redemptions (user_id, promotion_id);

ALTER TABLE public.subscription_promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_promotion_redemptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subscription_promotions_select_active ON public.subscription_promotions;
CREATE POLICY subscription_promotions_select_active ON public.subscription_promotions
  FOR SELECT TO authenticated, anon
  USING (is_active = true);

DROP POLICY IF EXISTS subscription_promotion_redemptions_select ON public.subscription_promotion_redemptions;
CREATE POLICY subscription_promotion_redemptions_select ON public.subscription_promotion_redemptions
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_platform_staff(auth.uid())
  );

DROP POLICY IF EXISTS subscription_promotion_redemptions_insert_own ON public.subscription_promotion_redemptions;
CREATE POLICY subscription_promotion_redemptions_insert_own ON public.subscription_promotion_redemptions
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3) Staff read-all (monitoring / anti-abuse consoles)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS billing_transactions_staff_read ON public.billing_transactions;
CREATE POLICY billing_transactions_staff_read ON public.billing_transactions
  FOR SELECT TO authenticated
  USING (public.is_platform_staff(auth.uid()));

DROP POLICY IF EXISTS user_subscriptions_staff_read ON public.user_subscriptions;
CREATE POLICY user_subscriptions_staff_read ON public.user_subscriptions
  FOR SELECT TO authenticated
  USING (public.is_platform_staff(auth.uid()));

DROP POLICY IF EXISTS saved_cards_staff_read ON public.saved_cards;
CREATE POLICY saved_cards_staff_read ON public.saved_cards
  FOR SELECT TO authenticated
  USING (public.is_platform_staff(auth.uid()));

DROP POLICY IF EXISTS extra_seats_requests_staff_read ON public.extra_seats_requests;
CREATE POLICY extra_seats_requests_staff_read ON public.extra_seats_requests
  FOR SELECT TO authenticated
  USING (public.is_platform_staff(auth.uid()));

-- ---------------------------------------------------------------------------
-- 4) Seed: welcome / first-use style (adjust dates as needed)
-- ---------------------------------------------------------------------------
INSERT INTO public.subscription_promotions (
  code, kind, value, trial_days, valid_from, valid_to, max_redemptions, per_user_limit,
  applies_user_types, title_ar, title_en, is_active
)
SELECT
  'WELCOME14',
  'trial_days'::text,
  0::numeric,
  14::int,
  now(),
  now() + interval '2 years',
  NULL::int,
  1::int,
  ARRAY['individual', 'marketer', 'office']::text[],
  N'تجربة 14 يوماً للميزات المدفوعة (وهمي حتى ربط البوابة)',
  '14-day trial window (mock until gateway)',
  true
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_promotions p WHERE lower(p.code) = lower('WELCOME14')
);

COMMENT ON TABLE public.billing_audit_log IS 'Immutable-style audit for billing state changes (trigger-fed).';
COMMENT ON TABLE public.subscription_promotions IS 'Campaigns, trials, and discounts; redemption enforced in app/RPC.';
