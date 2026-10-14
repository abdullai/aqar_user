-- طبقة الفريق داخل «إدارتي»: كل إعلانات وطلبات أعضاء المنشأة.
-- members see team inventory (personal workflow stays in «صفحتي»).
-- properties.type (not property_type).

BEGIN;

CREATE OR REPLACE FUNCTION public.org_team_inventory(p_org_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_listings jsonb := '[]'::jsonb;
  v_marketing jsonb := '[]'::jsonb;
  v_market jsonb := '[]'::jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF p_org_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'org_required');
  END IF;
  IF NOT (
    public.rls_is_org_owner(p_org_id, v_uid)
    OR public.rls_is_active_org_member(p_org_id, v_uid)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  WITH members AS (
    SELECT m.user_id AS uid
    FROM public.org_memberships m
    WHERE m.org_id = p_org_id
      AND m.status = 'active'
    UNION
    SELECT o.owner_user_id
    FROM public.org_units o
    WHERE o.id = p_org_id
      AND o.owner_user_id IS NOT NULL
  )
  SELECT COALESCE(
    jsonb_agg(row_to_json(x)::jsonb ORDER BY x.created_at DESC NULLS LAST),
    '[]'::jsonb
  )
  INTO v_listings
  FROM (
    SELECT
      p.id,
      p.title,
      p.status,
      p.views,
      p.price,
      p.created_at,
      p.owner_id AS member_user_id,
      p.city,
      p.type::text AS type_key,
      'listing'::text AS kind
    FROM public.properties p
    WHERE p.owner_id IN (SELECT uid FROM members)
      AND coalesce(p.status, '') IS DISTINCT FROM 'deleted'
    ORDER BY p.created_at DESC NULLS LAST
    LIMIT 200
  ) x;

  WITH members AS (
    SELECT m.user_id AS uid
    FROM public.org_memberships m
    WHERE m.org_id = p_org_id
      AND m.status = 'active'
    UNION
    SELECT o.owner_user_id
    FROM public.org_units o
    WHERE o.id = p_org_id
      AND o.owner_user_id IS NOT NULL
  )
  SELECT COALESCE(
    jsonb_agg(row_to_json(x)::jsonb ORDER BY x.created_at DESC NULLS LAST),
    '[]'::jsonb
  )
  INTO v_marketing
  FROM (
    SELECT
      r.id,
      r.title,
      r.status,
      r.price,
      r.created_at,
      r.owner_id AS member_user_id,
      r.city,
      r.workflow_stage,
      'marketing_request'::text AS kind
    FROM public.listing_requests r
    WHERE r.owner_id IN (SELECT uid FROM members)
    ORDER BY r.created_at DESC NULLS LAST
    LIMIT 200
  ) x;

  WITH members AS (
    SELECT m.user_id AS uid
    FROM public.org_memberships m
    WHERE m.org_id = p_org_id
      AND m.status = 'active'
    UNION
    SELECT o.owner_user_id
    FROM public.org_units o
    WHERE o.id = p_org_id
      AND o.owner_user_id IS NOT NULL
  )
  SELECT COALESCE(
    jsonb_agg(row_to_json(x)::jsonb ORDER BY x.created_at DESC NULLS LAST),
    '[]'::jsonb
  )
  INTO v_market
  FROM (
    SELECT
      q.id,
      q.title,
      q.status,
      q.created_at,
      q.requester_id AS member_user_id,
      q.city,
      q.property_type AS type_key,
      q.purpose,
      'market_request'::text AS kind
    FROM public.market_property_requests q
    WHERE q.requester_id IN (SELECT uid FROM members)
    ORDER BY q.created_at DESC NULLS LAST
    LIMIT 200
  ) x;

  RETURN jsonb_build_object(
    'ok', true,
    'listings', COALESCE(v_listings, '[]'::jsonb),
    'marketing_requests', COALESCE(v_marketing, '[]'::jsonb),
    'market_requests', COALESCE(v_market, '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.org_team_inventory(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.org_team_inventory(uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.org_team_inventory(uuid) IS
  'Active org members: listings + marketing requests + market requests owned by the team.';

COMMIT;
