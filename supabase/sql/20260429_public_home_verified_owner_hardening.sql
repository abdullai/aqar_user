-- =============================================================================
-- Public home feed hardening: published listings only + verified owners
--
-- Run in Supabase SQL Editor as project owner/postgres.
--
-- What this fixes:
--   1) Public home feed no longer exposes internal marketing stages.
--   2) Public home feed only exposes listings whose owner is verified or has
--      a FAL/REGA proof recorded in users_profiles.
--   3) Current public listings owned by unverified profiles are suppressed.
--      The edit-limit trigger is disabled only for this maintenance update and
--      re-enabled in the same transaction.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Helper used by RLS without depending on users_profiles SELECT policies.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.property_owner_public_verified(p_owner_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users_profiles up
    WHERE up.user_id = p_owner_id
      AND (
        COALESCE(up.verification_status::text, '') IN (
          'verified_business',
          'verified_identity',
          'approved'
        )
        OR NULLIF(TRIM(COALESCE(up.license_no::text, '')), '') IS NOT NULL
        OR up.rega_fal_snapshot IS NOT NULL
      )
  );
$$;

REVOKE ALL ON FUNCTION public.property_owner_public_verified(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.property_owner_public_verified(uuid) TO anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2) Public properties policy: only public/published statuses, no internal stages.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "properties_public_home_select" ON public.properties;

CREATE POLICY "properties_public_home_select"
ON public.properties
FOR SELECT
TO anon, authenticated
USING (
  status IS DISTINCT FROM 'deleted'
  AND COALESCE(home_feed_suppressed, false) = false
  AND public.property_owner_public_verified(owner_id)
  AND COALESCE(workflow_stage::text, '') NOT IN (
    'waiting_marketers',
    'marketer_selected',
    'contract_pending',
    'contract_sent',
    'contract_returned',
    'contract_signed',
    'permit_pending',
    'permit_issued',
    'inactive_72h'
  )
  AND (
    status IN (
      'published', 'active', 'available', 'live', 'reserved',
      'approved', 'listed', 'open', 'visible',
      'for_sale', 'for_rent', 'forsale', 'forrent'
    )
    OR (
      status = 'draft'
      AND workflow_stage IN ('published', 'reserved')
    )
  )
);

COMMENT ON POLICY "properties_public_home_select" ON public.properties IS
  'Public home feed: published/public statuses only, no internal marketing stages, owner must be verified/FAL-backed.';

-- -----------------------------------------------------------------------------
-- 3) Data cleanup: suppress currently public listings owned by unverified users.
--    The edit-limit trigger blocks this maintenance update, so disable only the
--    trigger(s) backed by enforce_property_edit_limit(), then enable them again.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT t.tgname
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE n.nspname = 'public'
      AND c.relname = 'properties'
      AND p.proname = 'enforce_property_edit_limit'
      AND NOT t.tgisinternal
  LOOP
    EXECUTE format('ALTER TABLE public.properties DISABLE TRIGGER %I', r.tgname);
  END LOOP;
END $$;

UPDATE public.properties p
SET home_feed_suppressed = true
WHERE p.status IN (
    'published', 'active', 'available', 'live', 'reserved',
    'approved', 'listed', 'open', 'visible',
    'for_sale', 'for_rent', 'forsale', 'forrent'
  )
  AND COALESCE(p.home_feed_suppressed, false) = false
  AND (
    NOT public.property_owner_public_verified(p.owner_id)
    OR COALESCE(p.workflow_stage::text, '') IN (
      'waiting_marketers',
      'marketer_selected',
      'contract_pending',
      'contract_sent',
      'contract_returned',
      'contract_signed',
      'permit_pending',
      'permit_issued',
      'inactive_72h'
    )
  );

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT t.tgname
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE n.nspname = 'public'
      AND c.relname = 'properties'
      AND p.proname = 'enforce_property_edit_limit'
      AND NOT t.tgisinternal
  LOOP
    EXECUTE format('ALTER TABLE public.properties ENABLE TRIGGER %I', r.tgname);
  END LOOP;
END $$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification checks.
-- -----------------------------------------------------------------------------
SELECT
  'public_visible_unverified_remaining' AS check_name,
  count(*)::bigint AS count
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
  AND COALESCE(p.home_feed_suppressed, false) = false
  AND COALESCE(p.workflow_stage::text, '') NOT IN (
    'waiting_marketers',
    'marketer_selected',
    'contract_pending',
    'contract_sent',
    'contract_returned',
    'contract_signed',
    'permit_pending',
    'permit_issued',
    'inactive_72h'
  )
  AND (
    p.status IN (
      'published', 'active', 'available', 'live', 'reserved',
      'approved', 'listed', 'open', 'visible',
      'for_sale', 'for_rent', 'forsale', 'forrent'
    )
    OR (
      p.status = 'draft'
      AND p.workflow_stage IN ('published', 'reserved')
    )
  )
  AND NOT public.property_owner_public_verified(p.owner_id);

SELECT
  p.id,
  p.title,
  p.status,
  p.workflow_stage,
  p.home_feed_suppressed,
  p.owner_id
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
  AND COALESCE(p.home_feed_suppressed, false) = false
  AND COALESCE(p.workflow_stage::text, '') NOT IN (
    'waiting_marketers',
    'marketer_selected',
    'contract_pending',
    'contract_sent',
    'contract_returned',
    'contract_signed',
    'permit_pending',
    'permit_issued',
    'inactive_72h'
  )
  AND (
    p.status IN (
      'published', 'active', 'available', 'live', 'reserved',
      'approved', 'listed', 'open', 'visible',
      'for_sale', 'for_rent', 'forsale', 'forrent'
    )
    OR (
      p.status = 'draft'
      AND p.workflow_stage IN ('published', 'reserved')
    )
  )
ORDER BY p.created_at DESC;
