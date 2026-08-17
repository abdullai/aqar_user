-- Subscription lifecycle audit + one-time retention prompt + churn feedback (RLS).

CREATE TABLE IF NOT EXISTS public.subscription_lifecycle_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  organization_id uuid REFERENCES public.org_units (id) ON DELETE SET NULL,
  subscription_id uuid REFERENCES public.user_subscriptions (id) ON DELETE SET NULL,
  event_type text NOT NULL CHECK (event_type IN (
    'subscription_started',
    'subscription_renewed',
    'subscription_upgraded',
    'subscription_cancel_requested',
    'subscription_cancel_finalized',
    'retention_offer_shown',
    'retention_offer_accepted',
    'retention_offer_declined',
    'churn_feedback'
  )),
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_subscription_lifecycle_events_user_created
  ON public.subscription_lifecycle_events (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_subscription_lifecycle_events_sub
  ON public.subscription_lifecycle_events (subscription_id, created_at DESC);

ALTER TABLE public.subscription_lifecycle_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subscription_lifecycle_events_select_own
  ON public.subscription_lifecycle_events;
CREATE POLICY subscription_lifecycle_events_select_own
  ON public.subscription_lifecycle_events FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS subscription_lifecycle_events_insert_own
  ON public.subscription_lifecycle_events;
CREATE POLICY subscription_lifecycle_events_insert_own
  ON public.subscription_lifecycle_events FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

COMMENT ON TABLE public.subscription_lifecycle_events IS 'Append-only style subscription actions for compliance and analytics.';

-- One-time retention modal per user (first cancellation flow).
CREATE TABLE IF NOT EXISTS public.user_subscription_retention_prompts (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  first_shown_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_subscription_retention_prompts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_subscription_retention_prompts_select_own
  ON public.user_subscription_retention_prompts;
CREATE POLICY user_subscription_retention_prompts_select_own
  ON public.user_subscription_retention_prompts FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS user_subscription_retention_prompts_insert_own
  ON public.user_subscription_retention_prompts;
CREATE POLICY user_subscription_retention_prompts_insert_own
  ON public.user_subscription_retention_prompts FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
