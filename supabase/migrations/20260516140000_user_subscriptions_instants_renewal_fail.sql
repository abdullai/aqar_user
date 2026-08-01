-- Instant subscription bounds (UTC) + auto-renew failure hints for strict client gates.
-- ends_at = first instant the subscription is NOT valid (exclusive upper bound).
-- Legacy rows: inclusive calendar end_date → ends_at = start of (end_date + 1 day) UTC.

ALTER TABLE public.user_subscriptions
  ADD COLUMN IF NOT EXISTS starts_at timestamptz,
  ADD COLUMN IF NOT EXISTS ends_at timestamptz,
  ADD COLUMN IF NOT EXISTS auto_renew_last_failure_at timestamptz,
  ADD COLUMN IF NOT EXISTS auto_renew_last_failure_reason text;

CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user_ends_at
  ON public.user_subscriptions (user_id, ends_at DESC);

-- Backfill: start_date / end_date treated as UTC calendar days; ends_at is exclusive (first invalid instant).
UPDATE public.user_subscriptions s
SET
  starts_at = COALESCE(s.starts_at, timezone('UTC', s.start_date::timestamp)),
  ends_at = COALESCE(s.ends_at, timezone('UTC', (s.end_date + 1)::timestamp))
WHERE s.starts_at IS NULL OR s.ends_at IS NULL;

COMMENT ON COLUMN public.user_subscriptions.starts_at IS 'UTC instant when paid period started; mirrors start_date for legacy.';
COMMENT ON COLUMN public.user_subscriptions.ends_at IS 'UTC exclusive end: valid while now < ends_at.';
COMMENT ON COLUMN public.user_subscriptions.auto_renew_last_failure_at IS 'Last automatic charge failure (webhook), if any.';
COMMENT ON COLUMN public.user_subscriptions.auto_renew_last_failure_reason IS 'Short failure code/message from gateway.';
