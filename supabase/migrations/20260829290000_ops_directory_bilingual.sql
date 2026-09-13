-- دليل التشغيل: اسم عربي/إنجليزي، رقم هوية/إقامة، هاتف، صفة — بلا UUID في العرض.
-- نفّذ بعد نجاح 20260829280000.

BEGIN;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS national_id text,
  ADD COLUMN IF NOT EXISTS unified_national_number text,
  ADD COLUMN IF NOT EXISTS phone text,
  ADD COLUMN IF NOT EXISTS secondary_phone text,
  ADD COLUMN IF NOT EXISTS license_no text,
  ADD COLUMN IF NOT EXISTS office_name text,
  ADD COLUMN IF NOT EXISTS full_name_en text,
  ADD COLUMN IF NOT EXISTS first_name_ar text,
  ADD COLUMN IF NOT EXISTS second_name_ar text,
  ADD COLUMN IF NOT EXISTS third_name_ar text,
  ADD COLUMN IF NOT EXISTS fourth_name_ar text,
  ADD COLUMN IF NOT EXISTS first_name_en text,
  ADD COLUMN IF NOT EXISTS second_name_en text,
  ADD COLUMN IF NOT EXISTS third_name_en text,
  ADD COLUMN IF NOT EXISTS fourth_name_en text;

CREATE OR REPLACE FUNCTION public._ops_person_json(up public.users_profiles)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_nid text;
  v_ar text;
  v_en text;
BEGIN
  IF up IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;
  v_nid := nullif(regexp_replace(coalesce(up.national_id, ''), '\D', '', 'g'), '');
  IF v_nid IS NULL THEN
    v_nid := nullif(regexp_replace(coalesce(up.unified_national_number, ''), '\D', '', 'g'), '');
  END IF;
  IF v_nid IS NULL AND coalesce(up.username, '') ~ '^[0-9]{10}$' THEN
    v_nid := up.username;
  END IF;
  v_ar := nullif(trim(concat_ws(' ',
    nullif(trim(up.first_name_ar), ''),
    nullif(trim(up.second_name_ar), ''),
    nullif(trim(up.third_name_ar), ''),
    nullif(trim(up.fourth_name_ar), '')
  )), '');
  IF v_ar IS NULL THEN
    v_ar := coalesce(nullif(trim(up.full_name_ar), ''), nullif(trim(up.full_name), ''), nullif(trim(up.office_name), ''), '');
  END IF;
  v_en := nullif(trim(concat_ws(' ',
    nullif(trim(up.first_name_en), ''),
    nullif(trim(up.second_name_en), ''),
    nullif(trim(up.third_name_en), ''),
    nullif(trim(up.fourth_name_en), '')
  )), '');
  IF v_en IS NULL THEN
    v_en := coalesce(nullif(trim(up.full_name_en), ''), '');
  END IF;
  RETURN jsonb_strip_nulls(jsonb_build_object(
    'user_id', up.user_id,
    'username', up.username,
    'national_id', v_nid,
    'first_name_ar', nullif(trim(up.first_name_ar), ''),
    'second_name_ar', nullif(trim(up.second_name_ar), ''),
    'third_name_ar', nullif(trim(up.third_name_ar), ''),
    'fourth_name_ar', nullif(trim(up.fourth_name_ar), ''),
    'first_name_en', nullif(trim(up.first_name_en), ''),
    'second_name_en', nullif(trim(up.second_name_en), ''),
    'third_name_en', nullif(trim(up.third_name_en), ''),
    'fourth_name_en', nullif(trim(up.fourth_name_en), ''),
    'full_name_ar', nullif(trim(up.full_name_ar), ''),
    'full_name_en', nullif(trim(up.full_name_en), ''),
    'full_name', nullif(trim(up.full_name), ''),
    'office_name', nullif(trim(up.office_name), ''),
    'phone', coalesce(nullif(trim(up.phone), ''), nullif(trim(up.secondary_phone), '')),
    'license_no', nullif(trim(up.license_no), ''),
    'account_type', coalesce(up.account_type, ''),
    'verification', coalesce(up.verification_status::text, ''),
    'name_ar', v_ar,
    'name_en', v_en,
    'name', v_ar
  ));
END;
$$;

CREATE OR REPLACE FUNCTION public._ops_person_matches(up public.users_profiles, p_q text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT
    coalesce(p_q, '') = ''
    OR (
      up IS NOT NULL
      AND (
    up.username ILIKE '%' || p_q || '%'
    OR coalesce(up.full_name_ar, '') ILIKE '%' || p_q || '%'
    OR coalesce(up.full_name_en, '') ILIKE '%' || p_q || '%'
    OR coalesce(up.full_name, '') ILIKE '%' || p_q || '%'
    OR coalesce(up.office_name, '') ILIKE '%' || p_q || '%'
    OR coalesce(up.first_name_ar, '') ILIKE '%' || p_q || '%'
    OR coalesce(up.first_name_en, '') ILIKE '%' || p_q || '%'
    OR coalesce(up.national_id, '') ILIKE '%' || p_q || '%'
    OR coalesce(up.unified_national_number, '') ILIKE '%' || p_q || '%'
    OR coalesce(up.phone, '') ILIKE '%' || p_q || '%'
    OR (
      regexp_replace(p_q, '\D', '', 'g') <> ''
      AND (
        regexp_replace(coalesce(up.national_id, ''), '\D', '', 'g')
          LIKE '%' || regexp_replace(p_q, '\D', '', 'g') || '%'
        OR regexp_replace(coalesce(up.username, ''), '\D', '', 'g')
          LIKE '%' || regexp_replace(p_q, '\D', '', 'g') || '%'
      )
    )
    OR (
      p_q ~* '^[0-9a-f]{8}-[0-9a-f-]{27}$'
      AND up.user_id::text ILIKE '%' || p_q || '%'
    )
      )
    );
$$;

CREATE OR REPLACE FUNCTION public._ops_profile_names(p_uid uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(public._ops_person_json(up), '{}'::jsonb)
  FROM public.users_profiles up
  WHERE up.user_id = p_uid;
$$;

CREATE OR REPLACE FUNCTION public._ops_profile_display_name(p_uid uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(
    nullif(public._ops_profile_names(p_uid)->>'name_ar', ''),
    nullif(public._ops_profile_names(p_uid)->>'name_en', ''),
    'عميل'
  );
$$;

CREATE OR REPLACE FUNCTION public._ops_profile_display_name_en(p_uid uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(
    nullif(public._ops_profile_names(p_uid)->>'name_en', ''),
    nullif(public._ops_profile_names(p_uid)->>'name_ar', ''),
    'Customer'
  );
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_directory(
  p_q text DEFAULT '',
  p_limit int DEFAULT 40,
  p_filter text DEFAULT 'all'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q text := trim(coalesce(p_q, ''));
  v_lim int := GREATEST(1, LEAST(coalesce(p_limit, 40), 80));
  v_f text := lower(trim(coalesce(p_filter, 'all')));
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'rows', coalesce((
      SELECT jsonb_agg(x)
      FROM (
        SELECT public._ops_person_json(up) || jsonb_build_object(
          'last_login', coalesce(up.last_verified_login_at, up.last_login_at),
          'last_seen', up.chat_last_seen_at,
          'online', (up.chat_last_seen_at IS NOT NULL AND up.chat_last_seen_at > now() - interval '2 minutes'),
          'last_logout', (
            SELECT max(ls.logout_at) FROM public.user_login_sessions ls
            WHERE ls.user_id = up.user_id AND ls.logout_at IS NOT NULL
          ),
          'is_staff', EXISTS (
            SELECT 1 FROM public.platform_staff s
            WHERE s.user_id = up.user_id AND coalesce(s.is_active, true)
          ),
          'banned', EXISTS (
            SELECT 1 FROM public.banned_accounts b
            WHERE b.user_id = up.user_id AND b.lifted_at IS NULL
          ),
          'locked', EXISTS (
            SELECT 1 FROM public.banned_accounts b
            WHERE b.user_id = up.user_id AND b.lifted_at IS NULL
              AND coalesce(b.blocks_app, true)
          ),
          'logins', (SELECT count(*)::int FROM public.user_login_sessions ls WHERE ls.user_id = up.user_id),
          'logouts', (SELECT count(*)::int FROM public.user_login_sessions ls WHERE ls.user_id = up.user_id AND ls.logout_at IS NOT NULL),
          'active_sessions', (
            SELECT count(*)::int FROM public.user_login_sessions ls
            WHERE ls.user_id = up.user_id AND coalesce(ls.is_active, false)
          ),
          'sales', (
            SELECT count(*)::int FROM public.billing_transactions bt
            WHERE bt.user_id = up.user_id AND bt.status = 'success'
          )
        ) AS x
        FROM public.users_profiles up
        WHERE public._ops_person_matches(up, v_q)
          AND (
            v_f = 'all'
            OR (v_f = 'staff' AND EXISTS (
              SELECT 1 FROM public.platform_staff s
              WHERE s.user_id = up.user_id AND coalesce(s.is_active, true)
            ))
            OR (v_f = 'banned' AND EXISTS (
              SELECT 1 FROM public.banned_accounts b
              WHERE b.user_id = up.user_id AND b.lifted_at IS NULL
            ))
            OR (v_f = 'locked' AND EXISTS (
              SELECT 1 FROM public.banned_accounts b
              WHERE b.user_id = up.user_id AND b.lifted_at IS NULL
                AND coalesce(b.blocks_app, true)
            ))
            OR (v_f = 'pending' AND (
              coalesce(up.verification_status::text, '') ILIKE '%pending%'
              OR coalesce(up.verification_status::text, '') ILIKE '%unverified%'
              OR coalesce(up.verification_status::text, '') IN ('none', 'rejected')
            ))
            OR (v_f = 'online' AND up.chat_last_seen_at > now() - interval '2 minutes')
            OR (v_f = 'offline' AND (
              up.chat_last_seen_at IS NULL
              OR up.chat_last_seen_at <= now() - interval '2 minutes'
            ))
            OR (v_f = 'active' AND coalesce(up.last_verified_login_at, up.last_login_at) > now() - interval '7 days')
            OR (v_f = 'inactive' AND coalesce(up.last_verified_login_at, up.last_login_at) <= now() - interval '7 days'
              AND coalesce(up.last_verified_login_at, up.last_login_at) >= now() - interval '30 days')
            OR (v_f = 'idle' AND (
              coalesce(up.last_verified_login_at, up.last_login_at) IS NULL
              OR coalesce(up.last_verified_login_at, up.last_login_at) < now() - interval '30 days'
            ))
            OR (v_f IN ('office', 'company', 'institution', 'marketer', 'agency')
                AND lower(coalesce(up.account_type, '')) = v_f)
            OR (v_f = 'owner' AND lower(coalesce(up.account_type, '')) IN (
              'owner_individual', 'individual_seller'
            ))
          )
        ORDER BY
          CASE WHEN up.chat_last_seen_at > now() - interval '2 minutes' THEN 0 ELSE 1 END,
          coalesce(up.chat_last_seen_at, up.last_verified_login_at, up.last_login_at) DESC NULLS LAST
        LIMIT v_lim
      ) z
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_team_list()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'rows', coalesce((
      SELECT jsonb_agg(
        coalesce(public._ops_person_json(up), jsonb_build_object('user_id', s.user_id))
        || jsonb_build_object(
          'is_owner', s.is_owner,
          'is_active', s.is_active,
          'can_support', s.can_support,
          'can_moderate', s.can_moderate,
          'can_finance', s.can_finance,
          'can_grant', s.can_grant,
          'can_ads', s.can_ads,
          'can_promo', s.can_promo,
          'can_ban', s.can_ban,
          'can_team_comms', s.can_team_comms,
          'roles', s.roles
        ) ORDER BY s.is_owner DESC, up.username
      )
      FROM public.platform_staff s
      LEFT JOIN public.users_profiles up ON up.user_id = s.user_id
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_team_time()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'users_online', (
      SELECT count(*)::int FROM public.users_profiles upn
      WHERE upn.chat_last_seen_at > now() - interval '2 minutes'
    ),
    'rows', coalesce((
      SELECT jsonb_agg(
        coalesce(public._ops_person_json(up), jsonb_build_object('user_id', s.user_id))
        || jsonb_build_object(
          'is_owner', s.is_owner,
          'is_active', s.is_active,
          'online', (up.chat_last_seen_at IS NOT NULL AND up.chat_last_seen_at > now() - interval '2 minutes'),
          'last_seen', up.chat_last_seen_at,
          'last_login', (
            SELECT max(ls.login_at) FROM public.user_login_sessions ls WHERE ls.user_id = s.user_id
          ),
          'last_logout', (
            SELECT max(ls.logout_at) FROM public.user_login_sessions ls
            WHERE ls.user_id = s.user_id AND ls.logout_at IS NOT NULL
          ),
          'seconds_today', coalesce((
            SELECT sum(
              GREATEST(0, coalesce(
                ls.session_duration_seconds,
                extract(epoch from (coalesce(ls.logout_at, now()) - ls.login_at))::int
              ))
            )::int
            FROM public.user_login_sessions ls
            WHERE ls.user_id = s.user_id AND ls.login_at >= date_trunc('day', now())
          ), 0),
          'seconds_7d', coalesce((
            SELECT sum(
              GREATEST(0, coalesce(
                ls.session_duration_seconds,
                extract(epoch from (coalesce(ls.logout_at, now()) - ls.login_at))::int
              ))
            )::int
            FROM public.user_login_sessions ls
            WHERE ls.user_id = s.user_id AND ls.login_at >= now() - interval '7 days'
          ), 0)
        ) ORDER BY s.is_owner DESC, up.username
      )
      FROM public.platform_staff s
      LEFT JOIN public.users_profiles up ON up.user_id = s.user_id
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_user_intel()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'most_logins', coalesce((
      SELECT jsonb_agg(
        coalesce(public._ops_person_json(up), jsonb_build_object('user_id', t.user_id))
        || jsonb_build_object('cnt', t.cnt)
        ORDER BY t.cnt DESC
      )
      FROM (
        SELECT user_id, count(*)::int AS cnt
        FROM public.user_login_sessions
        GROUP BY user_id
        ORDER BY count(*) DESC
        LIMIT 15
      ) t
      LEFT JOIN public.users_profiles up ON up.user_id = t.user_id
    ), '[]'::jsonb),
    'most_sales', coalesce((
      SELECT jsonb_agg(
        coalesce(public._ops_person_json(up), jsonb_build_object('user_id', t.user_id))
        || jsonb_build_object('cnt', t.cnt)
        ORDER BY t.cnt DESC
      )
      FROM (
        SELECT user_id, count(*)::int AS cnt
        FROM public.billing_transactions
        WHERE status = 'success'
        GROUP BY user_id
        ORDER BY count(*) DESC
        LIMIT 15
      ) t
      LEFT JOIN public.users_profiles up ON up.user_id = t.user_id
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_promo_redemptions(
  p_id uuid,
  p_q text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q text := trim(coalesce(p_q, ''));
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'rows', coalesce((
      SELECT jsonb_agg(
        coalesce(public._ops_person_json(up), jsonb_build_object('user_id', r.user_id))
        || jsonb_build_object(
          'created_at', r.created_at,
          'billing_transaction_id', r.billing_transaction_id,
          'amount', bt.amount
        ) ORDER BY r.created_at DESC
      )
      FROM public.subscription_promotion_redemptions r
      LEFT JOIN public.users_profiles up ON up.user_id = r.user_id
      LEFT JOIN public.billing_transactions bt ON bt.id = r.billing_transaction_id
      WHERE r.promotion_id = p_id
        AND r.billing_transaction_id IS NOT NULL
        AND (v_q = '' OR public._ops_person_matches(up, v_q)
             OR coalesce(up.account_type, '') ILIKE '%' || v_q || '%')
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_campaign_receipts(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'delivered', (SELECT count(*)::int FROM public.ops_push_receipts WHERE campaign_id = p_id),
    'read', (SELECT count(*)::int FROM public.ops_push_receipts WHERE campaign_id = p_id AND read_at IS NOT NULL),
    'rows', coalesce((
      SELECT jsonb_agg(
        coalesce(public._ops_person_json(up), jsonb_build_object('user_id', r.user_id))
        || jsonb_build_object(
          'delivered_at', r.delivered_at,
          'read_at', r.read_at
        ) ORDER BY r.delivered_at DESC
      )
      FROM public.ops_push_receipts r
      LEFT JOIN public.users_profiles up ON up.user_id = r.user_id
      WHERE r.campaign_id = p_id
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public._ops_person_json(public.users_profiles) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._ops_person_matches(public.users_profiles, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._ops_profile_names(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._ops_profile_display_name_en(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_directory(text, int, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_team_list() TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_team_time() TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_user_intel() TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_promo_redemptions(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_campaign_receipts(uuid) TO authenticated;

COMMIT;
