-- Remove user identities and profile counts from the public market snapshot.
BEGIN;

CREATE OR REPLACE FUNCTION public.get_market_insights_snapshot()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  lr_total int := 0;
  lr_by_status jsonb := '{}'::jsonb;
  org_reg int := 0;
  listings_obj jsonb;
BEGIN
  IF to_regclass('public.listing_requests') IS NOT NULL THEN
    SELECT COUNT(*)::int INTO lr_total FROM public.listing_requests;
    SELECT COALESCE(
      (SELECT jsonb_object_agg(status_key, cnt)
       FROM (
         SELECT COALESCE(lr.status::text, 'unknown') AS status_key,
                COUNT(*)::int AS cnt
         FROM public.listing_requests lr
         GROUP BY lr.status
       ) s),
      '{}'::jsonb
    ) INTO lr_by_status;
  END IF;

  IF to_regclass('public.org_units') IS NOT NULL THEN
    SELECT COUNT(*)::int INTO org_reg FROM public.org_units;
  END IF;

  WITH pub AS (
    SELECT
      p.owner_id,
      p.created_at,
      COALESCE(p.is_featured, false) AS is_featured,
      COALESCE(p.type::text, 'unknown') AS prop_type
    FROM public.properties p
    WHERE p.status IN (
      'published', 'active', 'available', 'live', 'reserved', 'approved'
    )
  ),
  totals AS (
    SELECT
      COUNT(*)::int AS published_total,
      COUNT(*) FILTER (WHERE pub.created_at >= (now() - interval '7 days'))::int AS new_last_7d,
      COUNT(*) FILTER (WHERE pub.created_at >= (now() - interval '30 days'))::int AS new_last_30d,
      COUNT(*) FILTER (WHERE pub.is_featured)::int AS featured_total
    FROM pub
  ),
  by_account AS (
    SELECT COALESCE(up.account_type::text, 'user') AS k, COUNT(*)::int AS c
    FROM pub p
    LEFT JOIN public.users_profiles up ON up.user_id = p.owner_id
    GROUP BY COALESCE(up.account_type::text, 'user')
  ),
  by_type AS (
    SELECT pub.prop_type AS k, COUNT(*)::int AS c
    FROM pub
    GROUP BY pub.prop_type
  )
  SELECT jsonb_build_object(
    'published_total', t.published_total,
    'new_last_7d', t.new_last_7d,
    'new_last_30d', t.new_last_30d,
    'featured_total', t.featured_total,
    'by_account_type', COALESCE((SELECT jsonb_object_agg(k, c) FROM by_account), '{}'::jsonb),
    'by_property_type', COALESCE((SELECT jsonb_object_agg(k, c) FROM by_type), '{}'::jsonb)
  )
  INTO listings_obj
  FROM totals t;

  RETURN jsonb_build_object(
    'generated_at', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'listings', COALESCE(listings_obj, jsonb_build_object(
      'published_total', 0,
      'new_last_7d', 0,
      'new_last_30d', 0,
      'featured_total', 0,
      'by_account_type', '{}'::jsonb,
      'by_property_type', '{}'::jsonb
    )),
    'listing_requests', jsonb_build_object(
      'total', lr_total,
      'by_status', COALESCE(lr_by_status, '{}'::jsonb)
    ),
    'orgs', jsonb_build_object('registered', org_reg)
  );
END;
$$;

COMMENT ON FUNCTION public.get_market_insights_snapshot() IS
  'Aggregated public market snapshot; excludes user identities, profile counts, and rankings.';

REVOKE ALL ON FUNCTION public.get_market_insights_snapshot() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_market_insights_snapshot()
  TO anon, authenticated, service_role;

COMMIT;
