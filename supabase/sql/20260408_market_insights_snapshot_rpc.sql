-- =============================================================================
-- لقطة موحّدة لتحليل السوق (أرقام + لوائح ترتيب) — SECURITY DEFINER
-- نفّذ في Supabase SQL Editor. يمنح anon + authenticated حق التنفيذ.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_market_insights_snapshot()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  lr_total int := 0;
  lr_by_status jsonb := '{}'::jsonb;
  org_reg int := 0;
  listings_obj jsonb;
  top_pub jsonb := '[]'::jsonb;
  top_org jsonb := '[]'::jsonb;
  viewer_obj jsonb := 'null'::jsonb;
  v_dist_pub int := 0;
  v_prof int := 0;
  extras_obj jsonb := '{}'::jsonb;
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
      p.id,
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

  WITH pub AS (
    SELECT p.id, p.owner_id
    FROM public.properties p
    WHERE p.status IN (
      'published', 'active', 'available', 'live', 'reserved', 'approved'
    )
  ),
  owner_counts AS (
    SELECT p.owner_id, COUNT(*)::int AS c
    FROM pub p
    GROUP BY p.owner_id
  ),
  ranked_global AS (
    SELECT
      oc.owner_id,
      oc.c,
      RANK() OVER (ORDER BY oc.c DESC) AS rnk
    FROM owner_counts oc
  ),
  enriched AS (
    SELECT
      rg.rnk,
      rg.owner_id,
      rg.c,
      COALESCE(
        NULLIF(TRIM(up.full_name_ar), ''),
        NULLIF(TRIM(up.full_name_en), ''),
        NULLIF(TRIM(up.full_name), ''),
        NULLIF(TRIM(up.username), ''),
        '—'
      ) AS display_name,
      COALESCE(up.account_type::text, 'user') AS account_type
    FROM ranked_global rg
    LEFT JOIN public.users_profiles up ON up.user_id = rg.owner_id
  )
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'rank', e.rnk,
        'user_id', e.owner_id,
        'display_name', e.display_name,
        'account_type', e.account_type,
        'listing_count', e.c
      ) ORDER BY e.rnk
    ),
    '[]'::jsonb
  )
  INTO top_pub
  FROM (
    SELECT * FROM enriched ORDER BY rnk ASC LIMIT 15
  ) e;

  IF to_regclass('public.org_units') IS NOT NULL THEN
    WITH pub AS (
      SELECT p.id, p.owner_id
      FROM public.properties p
      WHERE p.status IN (
        'published', 'active', 'available', 'live', 'reserved', 'approved'
      )
    ),
    org_listing AS (
      SELECT
        ou.id AS org_id,
        ou.account_type::text AS org_kind,
        COUNT(p.id)::int AS listing_count,
        COALESCE(
          NULLIF(TRIM(up_own.full_name_ar), ''),
          NULLIF(TRIM(up_own.full_name_en), ''),
          NULLIF(TRIM(up_own.full_name), ''),
          NULLIF(TRIM(up_own.username), ''),
          ou.account_type::text
        ) AS label
      FROM public.org_units ou
      INNER JOIN public.users_profiles up_own ON up_own.user_id = ou.owner_user_id
      INNER JOIN public.users_profiles upm ON upm.org_id = ou.id
      INNER JOIN pub p ON p.owner_id = upm.user_id
      GROUP BY ou.id, ou.account_type, up_own.full_name_ar, up_own.full_name_en,
               up_own.full_name, up_own.username
    )
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'org_id', o.org_id,
          'kind', o.org_kind,
          'label', o.label,
          'listing_count', o.listing_count
        ) ORDER BY o.listing_count DESC
      ),
      '[]'::jsonb
    )
    INTO top_org
    FROM (
      SELECT * FROM org_listing ORDER BY listing_count DESC LIMIT 8
    ) o;
  END IF;

  IF v_uid IS NOT NULL THEN
    WITH pub AS (
      SELECT p.owner_id
      FROM public.properties p
      WHERE p.status IN (
        'published', 'active', 'available', 'live', 'reserved', 'approved'
      )
    ),
    owner_counts AS (
      SELECT p.owner_id, COUNT(*)::int AS c
      FROM pub p
      GROUP BY p.owner_id
    ),
    ranked_global AS (
      SELECT
        oc.owner_id,
        oc.c,
        RANK() OVER (ORDER BY oc.c DESC) AS rnk
      FROM owner_counts oc
    )
    SELECT jsonb_build_object(
      'user_id', v_uid,
      'published_listings', COALESCE((SELECT c FROM owner_counts WHERE owner_id = v_uid), 0),
      'rank_global', (SELECT r.rnk FROM ranked_global r WHERE r.owner_id = v_uid LIMIT 1),
      'account_type', (
        SELECT COALESCE(up.account_type::text, 'user')
        FROM public.users_profiles up
        WHERE up.user_id = v_uid
        LIMIT 1
      )
    )
    INTO viewer_obj;
  END IF;

  SELECT COUNT(DISTINCT p.owner_id)::int
  INTO v_dist_pub
  FROM public.properties p
  WHERE p.status IN (
    'published', 'active', 'available', 'live', 'reserved', 'approved'
  );

  IF to_regclass('public.users_profiles') IS NOT NULL THEN
    SELECT COUNT(*)::int INTO v_prof FROM public.users_profiles;
  ELSE
    v_prof := 0;
  END IF;

  extras_obj := jsonb_build_object(
    'distinct_listing_publishers', v_dist_pub,
    'registered_profiles', v_prof
  );

  RETURN jsonb_build_object(
    'generated_at', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'listings', listings_obj,
    'listing_requests', jsonb_build_object(
      'total', lr_total,
      'by_status', lr_by_status
    ),
    'orgs', jsonb_build_object(
      'registered', org_reg,
      'top', COALESCE(top_org, '[]'::jsonb)
    ),
    'leaderboard', jsonb_build_object(
      'top_publishers', COALESCE(top_pub, '[]'::jsonb)
    ),
    'viewer', viewer_obj,
    'extras', extras_obj
  );
END;
$$;

COMMENT ON FUNCTION public.get_market_insights_snapshot() IS
  'Aggregated market snapshot (listings, requests, orgs, leaderboard). SECURITY DEFINER.';

REVOKE ALL ON FUNCTION public.get_market_insights_snapshot() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_market_insights_snapshot() TO anon, authenticated;
