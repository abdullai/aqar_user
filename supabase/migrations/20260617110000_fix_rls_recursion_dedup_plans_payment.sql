-- =============================================================================
-- 2026-06-17 — إصلاح 500 (تكرار RLS) + باقة واحدة لكل دور + كتالوج بدون تكرار
-- =============================================================================
-- الأعراض:
--   • user_subscriptions?select=*,plan:subscription_plans(*) → 500
--   • org_units?owner_user_id=eq… → 500 (تكرار org_units ↔ org_memberships)
--   • باقات مكررة (أساسية / أساسي / أساسي) في الواجهة
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- (A) دوال SECURITY DEFINER لكسر حلقات RLS
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rls_user_owns_plan(p_plan_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_subscriptions us
    WHERE us.plan_id = p_plan_id
      AND us.user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.rls_is_org_owner(p_org_id uuid, p_uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.org_units o
    WHERE o.id = p_org_id
      AND o.owner_user_id = p_uid
  );
$$;

CREATE OR REPLACE FUNCTION public.rls_is_active_org_member(p_org_id uuid, p_uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.org_memberships m
    WHERE m.org_id = p_org_id
      AND m.user_id = p_uid
      AND m.status = 'active'
  );
$$;

REVOKE ALL ON FUNCTION public.rls_user_owns_plan(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rls_user_owns_plan(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.rls_is_org_owner(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rls_is_org_owner(uuid, uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.rls_is_active_org_member(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rls_is_active_org_member(uuid, uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- (B) subscription_plans — بدون subquery على user_subscriptions داخل السياسة
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS subscription_plans_select_active ON public.subscription_plans;
DROP POLICY IF EXISTS subscription_plans_select_subscribed ON public.subscription_plans;
DROP POLICY IF EXISTS subscription_plans_select_catalog ON public.subscription_plans;
DROP POLICY IF EXISTS subscription_plans_select_owned_inactive ON public.subscription_plans;

CREATE POLICY subscription_plans_select_catalog ON public.subscription_plans
  FOR SELECT TO authenticated, anon
  USING (is_active = true);

CREATE POLICY subscription_plans_select_owned_inactive ON public.subscription_plans
  FOR SELECT TO authenticated
  USING (
    NOT is_active
    AND public.rls_user_owns_plan(id)
  );

-- ---------------------------------------------------------------------------
-- (C) org_units / org_memberships — بدون تكرار متبادل
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS org_units_select_member ON public.org_units;
CREATE POLICY org_units_select_member ON public.org_units
  FOR SELECT TO authenticated
  USING (
    owner_user_id = auth.uid()
    OR public.rls_is_active_org_member(id, auth.uid())
  );

DROP POLICY IF EXISTS org_memberships_select ON public.org_memberships;
CREATE POLICY org_memberships_select ON public.org_memberships
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.rls_is_org_owner(org_id, auth.uid())
  );

-- ---------------------------------------------------------------------------
-- (D) إبقاء باقة نشطة واحدة فقط لكل (user_type, sort_order) غير تجريبية
-- ---------------------------------------------------------------------------
WITH ranked AS (
  SELECT
    sp.id,
    row_number() OVER (
      PARTITION BY sp.user_type, sp.sort_order
      ORDER BY
        CASE
          WHEN sp.user_type = 'marketer' AND sp.sort_order = 1 AND sp.price_monthly = 99 THEN 0
          WHEN sp.user_type = 'office' AND sp.sort_order = 2 AND sp.price_monthly = 149 THEN 0
          WHEN sp.user_type = 'institution' AND sp.sort_order = 2 AND sp.price_monthly = 149 THEN 0
          WHEN sp.user_type = 'company' AND sp.sort_order = 3 AND sp.price_monthly = 499 THEN 0
          WHEN sp.user_type = 'individual' AND sp.sort_order = 1 AND sp.price_monthly = 49 THEN 0
          ELSE 1
        END,
        sp.created_at DESC NULLS LAST,
        sp.id DESC
    ) AS rn
  FROM public.subscription_plans sp
  WHERE coalesce(sp.is_trial_plan, false) = false
    AND sp.is_active = true
)
UPDATE public.subscription_plans sp
   SET is_active = false
  FROM ranked r
 WHERE sp.id = r.id
   AND r.rn > 1;

-- تجريبية واحدة نشطة لكل دور
WITH trial_ranked AS (
  SELECT
    sp.id,
    row_number() OVER (
      PARTITION BY sp.user_type
      ORDER BY sp.created_at DESC NULLS LAST, sp.id DESC
    ) AS rn
  FROM public.subscription_plans sp
  WHERE coalesce(sp.is_trial_plan, false) = true
    AND sp.is_active = true
)
UPDATE public.subscription_plans sp
   SET is_active = false
  FROM trial_ranked r
 WHERE sp.id = r.id
   AND r.rn > 1;

-- ---------------------------------------------------------------------------
-- (E) RPC الكتالوج — صف كانوني واحد لكل sort_order
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_subscription_catalog_plans()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_at text;
  v_plan_type text;
  v_allowed int[];
  v_rows jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required', 'plans', '[]'::jsonb);
  END IF;

  SELECT coalesce(nullif(trim(up.account_type::text), ''), 'user')
  INTO v_at
  FROM public.users_profiles up
  WHERE up.user_id = v_uid;

  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found', 'plans', '[]'::jsonb);
  END IF;

  v_plan_type := CASE lower(trim(v_at))
    WHEN 'marketer' THEN 'marketer'
    WHEN 'office' THEN 'office'
    WHEN 'agency' THEN 'office'
    WHEN 'company' THEN 'company'
    WHEN 'institution' THEN 'institution'
    WHEN 'individual_seller' THEN 'individual'
    WHEN 'owner_individual' THEN 'individual'
    WHEN 'individual' THEN 'individual'
    WHEN 'public_user' THEN 'individual'
    WHEN 'user' THEN 'individual'
    ELSE 'individual'
  END;

  v_allowed := CASE v_plan_type
    WHEN 'marketer' THEN ARRAY[1, 21, 22, 23]
    WHEN 'office' THEN ARRAY[2, 21, 22, 23]
    WHEN 'institution' THEN ARRAY[2, 21, 22, 23]
    WHEN 'company' THEN ARRAY[3]
    ELSE ARRAY[1, 11, 12, 13]
  END;

  SELECT coalesce(jsonb_agg(row_data ORDER BY sort_order), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT DISTINCT ON (sp.sort_order)
      sp.sort_order,
      to_jsonb(sp) AS row_data
    FROM public.subscription_plans sp
    WHERE sp.is_active = true
      AND coalesce(sp.is_trial_plan, false) = false
      AND sp.user_type = v_plan_type
      AND sp.sort_order = ANY (v_allowed)
    ORDER BY sp.sort_order, sp.created_at DESC NULLS LAST, sp.id DESC
  ) canon;

  IF v_rows IS NULL OR jsonb_array_length(v_rows) = 0 THEN
    SELECT coalesce(jsonb_agg(row_data ORDER BY sort_order), '[]'::jsonb)
    INTO v_rows
    FROM (
      SELECT DISTINCT ON (sp.sort_order)
        sp.sort_order,
        to_jsonb(sp) AS row_data
      FROM public.subscription_plans sp
      WHERE sp.is_active = true
        AND coalesce(sp.is_trial_plan, false) = false
        AND sp.user_type = v_plan_type
      ORDER BY sp.sort_order, sp.created_at DESC NULLS LAST, sp.id DESC
    ) fallback;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'account_type', v_at,
    'plan_user_type', v_plan_type,
    'plans', coalesce(v_rows, '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_subscription_catalog_plans() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_subscription_catalog_plans()
  TO authenticated, service_role;

COMMIT;
