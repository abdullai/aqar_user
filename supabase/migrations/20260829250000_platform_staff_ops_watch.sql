-- مراقبة اشتراكات، حضور الفريق، حضور المستخدمين، حملات بلا سقف 400، إيصالات، حذف صندوق الإشعار بعد نهاية الحملة.
-- نفّذ بعد نجاح 20260829240000.

BEGIN;

ALTER TABLE public.ops_push_campaigns
  ADD COLUMN IF NOT EXISTS send_all boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'broadcast',
  ADD COLUMN IF NOT EXISTS cursor_user_id uuid,
  ADD COLUMN IF NOT EXISTS inbox_purged_at timestamptz;

CREATE TABLE IF NOT EXISTS public.ops_push_receipts (
  campaign_id uuid NOT NULL REFERENCES public.ops_push_campaigns (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  delivered_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz,
  PRIMARY KEY (campaign_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_ops_push_receipts_campaign
  ON public.ops_push_receipts (campaign_id, delivered_at DESC);

ALTER TABLE public.ops_push_receipts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ops_push_receipts_staff_read ON public.ops_push_receipts;
CREATE POLICY ops_push_receipts_staff_read ON public.ops_push_receipts
  FOR SELECT TO authenticated
  USING (public.is_platform_staff(auth.uid()));

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
        SELECT jsonb_build_object(
          'user_id', up.user_id,
          'username', up.username,
          'account_type', coalesce(up.account_type, ''),
          'name', coalesce(nullif(trim(up.full_name_ar), ''), nullif(trim(up.full_name), ''), ''),
          'verification', coalesce(up.verification_status::text, ''),
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
        WHERE (v_q = ''
           OR up.username ILIKE '%' || v_q || '%'
           OR coalesce(up.full_name_ar, '') ILIKE '%' || v_q || '%'
           OR coalesce(up.full_name, '') ILIKE '%' || v_q || '%'
           OR up.user_id::text ILIKE '%' || v_q || '%')
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
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', s.user_id,
        'username', up.username,
        'name', coalesce(nullif(trim(up.full_name_ar), ''), nullif(trim(up.full_name), ''), ''),
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
      ) ORDER BY s.is_owner DESC, up.username)
      FROM public.platform_staff s
      LEFT JOIN public.users_profiles up ON up.user_id = s.user_id
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_billing_watch()
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
  IF NOT (
    coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = auth.uid()), false)
    OR coalesce((SELECT can_finance FROM public.platform_staff WHERE user_id = auth.uid()), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_finance');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'subs_active', (SELECT count(*)::int FROM public.user_subscriptions WHERE status = 'active'),
    'subs_pending', (SELECT count(*)::int FROM public.user_subscriptions WHERE status = 'pending'),
    'subs_expired', (SELECT count(*)::int FROM public.user_subscriptions WHERE status = 'expired'),
    'subs_cancelled', (SELECT count(*)::int FROM public.user_subscriptions WHERE status = 'cancelled'),
    'pay_success_7d', (SELECT count(*)::int FROM public.billing_transactions WHERE status = 'success' AND created_at > now() - interval '7 days'),
    'pay_pending', (SELECT count(*)::int FROM public.billing_transactions WHERE status IN ('pending', 'initiated') AND created_at < now() - interval '1 hour'),
    'pay_refunded_30d', (SELECT count(*)::int FROM public.billing_transactions WHERE status ILIKE '%refund%' AND created_at > now() - interval '30 days'),
    'dup_gateway', coalesce((
      SELECT count(*)::int FROM (
        SELECT gateway_transaction_id
        FROM public.billing_transactions
        WHERE nullif(trim(coalesce(gateway_transaction_id, '')), '') IS NOT NULL
          AND status = 'success'
        GROUP BY gateway_transaction_id
        HAVING count(*) > 1
      ) d
    ), 0),
    'dup_rows', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'gateway_transaction_id', t.gateway_transaction_id,
        'cnt', t.cnt
      ))
      FROM (
        SELECT gateway_transaction_id, count(*)::int AS cnt
        FROM public.billing_transactions
        WHERE nullif(trim(coalesce(gateway_transaction_id, '')), '') IS NOT NULL
          AND status = 'success'
        GROUP BY gateway_transaction_id
        HAVING count(*) > 1
        LIMIT 20
      ) t
    ), '[]'::jsonb)
  );
END;
$$;

DROP FUNCTION IF EXISTS public.platform_staff_upsert_campaign(text, text, text, text, text, text, text, timestamptz, timestamptz, text);
DROP FUNCTION IF EXISTS public.platform_staff_upsert_campaign(text, text, text, text, text, text, text, timestamptz, timestamptz, text, boolean, text);

CREATE OR REPLACE FUNCTION public.platform_staff_upsert_campaign(
  p_title_ar text,
  p_title_en text,
  p_body_ar text,
  p_body_en text,
  p_media_url text DEFAULT NULL,
  p_deep_route text DEFAULT 'user_dashboard',
  p_account_type text DEFAULT '',
  p_starts_at timestamptz DEFAULT now(),
  p_ends_at timestamptz DEFAULT NULL,
  p_target_q text DEFAULT '',
  p_send_all boolean DEFAULT false,
  p_kind text DEFAULT 'broadcast'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_kind text := lower(trim(coalesce(p_kind, 'broadcast')));
BEGIN
  IF v_uid IS NULL OR NOT public.is_platform_staff(v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT (
    coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_ads FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_team_comms FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_finance FROM public.platform_staff WHERE user_id = v_uid), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_campaign');
  END IF;
  IF v_kind NOT IN ('broadcast', 'idle_nudge') THEN
    v_kind := 'broadcast';
  END IF;
  INSERT INTO public.ops_push_campaigns (
    created_by, title_ar, title_en, body_ar, body_en, media_url,
    deep_route, account_type, target_q, starts_at, ends_at, status,
    send_all, kind
  ) VALUES (
    v_uid,
    coalesce(p_title_ar, ''),
    coalesce(p_title_en, ''),
    coalesce(p_body_ar, ''),
    coalesce(p_body_en, ''),
    nullif(trim(coalesce(p_media_url, '')), ''),
    coalesce(nullif(trim(p_deep_route), ''), 'user_dashboard'),
    coalesce(p_account_type, ''),
    trim(coalesce(p_target_q, '')),
    coalesce(p_starts_at, now()),
    p_ends_at,
    'scheduled',
    coalesce(p_send_all, false),
    v_kind
  ) RETURNING id INTO v_id;
  PERFORM public._staff_audit('campaign', 'ops_push_campaigns', v_id::text, jsonb_build_object('kind', v_kind, 'send_all', p_send_all));
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public._ops_purge_campaign_inbox(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.in_app_notifications
  WHERE type = 'ops_push'
    AND (
      entity_id = p_id
      OR coalesce(data->>'campaign_id', '') = p_id::text
    );
  UPDATE public.ops_push_campaigns
  SET inbox_purged_at = now()
  WHERE id = p_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_dispatch_campaign(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  c public.ops_push_campaigns%ROWTYPE;
  r record;
  v_n int := 0;
  v_q text;
  v_batch int;
  v_last uuid;
BEGIN
  IF v_uid IS NULL OR NOT public.is_platform_staff(v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  SELECT * INTO c FROM public.ops_push_campaigns WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  IF now() < c.starts_at THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_started', 'status', 'scheduled');
  END IF;
  IF c.ends_at IS NOT NULL AND now() > c.ends_at THEN
    UPDATE public.ops_push_campaigns SET status = 'expired' WHERE id = p_id;
    PERFORM public._ops_purge_campaign_inbox(p_id);
    RETURN jsonb_build_object('ok', false, 'error', 'expired');
  END IF;

  v_q := trim(coalesce(c.target_q, ''));
  v_batch := CASE WHEN coalesce(c.send_all, false) THEN 800 ELSE 400 END;
  v_last := c.cursor_user_id;

  FOR r IN
    SELECT up.user_id
    FROM public.users_profiles up
    WHERE (v_last IS NULL OR up.user_id > v_last)
      AND (c.account_type = '' OR lower(coalesce(up.account_type, '')) = lower(c.account_type))
      AND (
        v_q = ''
        OR up.username ILIKE '%' || v_q || '%'
        OR coalesce(up.full_name_ar, '') ILIKE '%' || v_q || '%'
        OR coalesce(up.full_name, '') ILIKE '%' || v_q || '%'
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.banned_accounts b
        WHERE b.user_id = up.user_id AND b.lifted_at IS NULL
      )
      AND (
        (c.kind = 'idle_nudge' AND (
          coalesce(up.last_verified_login_at, up.last_login_at) IS NULL
          OR coalesce(up.last_verified_login_at, up.last_login_at) < now() - interval '30 days'
        ))
        OR (coalesce(c.kind, 'broadcast') <> 'idle_nudge' AND (
          coalesce(up.last_verified_login_at, up.last_login_at) IS NULL
          OR coalesce(up.last_verified_login_at, up.last_login_at) >= now() - interval '90 days'
        ))
      )
    ORDER BY up.user_id
    LIMIT v_batch
  LOOP
    BEGIN
      PERFORM public.workflow_create_notification(
        r.user_id,
        'ops_push',
        coalesce(nullif(trim(c.title_ar), ''), 'إشعار المنصة'),
        coalesce(nullif(trim(c.body_ar), ''), c.body_en),
        'ops',
        p_id,
        jsonb_build_object(
          'title_ar', c.title_ar,
          'title_en', c.title_en,
          'body_ar', c.body_ar,
          'body_en', c.body_en,
          'media_url', c.media_url,
          'deep_route', c.deep_route,
          'campaign_id', p_id
        )
      );
      INSERT INTO public.ops_push_receipts (campaign_id, user_id)
      VALUES (p_id, r.user_id)
      ON CONFLICT DO NOTHING;
      v_n := v_n + 1;
      v_last := r.user_id;
    EXCEPTION WHEN OTHERS THEN
      v_last := r.user_id;
    END;
  END LOOP;

  UPDATE public.ops_push_campaigns
  SET
    cursor_user_id = v_last,
    sent_count = sent_count + v_n,
    status = CASE
      WHEN v_n < v_batch THEN 'sent'
      ELSE 'sending'
    END
  WHERE id = p_id;

  PERFORM public._staff_audit(
    'dispatch_campaign', 'ops_push_campaigns', p_id::text,
    jsonb_build_object('batch', v_n, 'send_all', c.send_all)
  );
  RETURN jsonb_build_object('ok', true, 'sent', v_n, 'status', CASE WHEN v_n < v_batch THEN 'sent' ELSE 'sending' END);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_run_due_campaigns()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_n int := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  FOR r IN
    SELECT id FROM public.ops_push_campaigns
    WHERE status IN ('scheduled', 'sent', 'sending', 'expired')
      AND ends_at IS NOT NULL AND ends_at <= now()
      AND inbox_purged_at IS NULL
    LIMIT 20
  LOOP
    UPDATE public.ops_push_campaigns SET status = 'expired' WHERE id = r.id AND status <> 'expired';
    PERFORM public._ops_purge_campaign_inbox(r.id);
  END LOOP;
  FOR r IN
    SELECT id FROM public.ops_push_campaigns
    WHERE status IN ('scheduled', 'sending')
      AND starts_at <= now()
      AND (ends_at IS NULL OR ends_at > now())
    LIMIT 8
  LOOP
    PERFORM public.platform_staff_dispatch_campaign(r.id);
    v_n := v_n + 1;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'ran', v_n);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_list_campaigns()
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
      SELECT jsonb_agg(jsonb_build_object(
        'id', c.id,
        'title_ar', c.title_ar,
        'title_en', c.title_en,
        'body_ar', c.body_ar,
        'body_en', c.body_en,
        'account_type', c.account_type,
        'target_q', c.target_q,
        'deep_route', c.deep_route,
        'starts_at', c.starts_at,
        'ends_at', c.ends_at,
        'status', c.status,
        'sent_count', c.sent_count,
        'media_url', c.media_url,
        'send_all', c.send_all,
        'kind', c.kind,
        'inbox_purged_at', c.inbox_purged_at
      ) ORDER BY c.created_at DESC)
      FROM public.ops_push_campaigns c
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
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', r.user_id,
        'username', up.username,
        'name', coalesce(nullif(trim(up.full_name_ar), ''), nullif(trim(up.full_name), ''), ''),
        'delivered_at', r.delivered_at,
        'read_at', r.read_at
      ) ORDER BY r.delivered_at DESC)
      FROM public.ops_push_receipts r
      LEFT JOIN public.users_profiles up ON up.user_id = r.user_id
      WHERE r.campaign_id = p_id
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._ops_push_receipt_on_read()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cid uuid;
BEGIN
  IF NEW.is_read IS TRUE AND OLD.is_read IS DISTINCT FROM TRUE
     AND NEW.type = 'ops_push' THEN
    v_cid := NEW.entity_id;
    IF v_cid IS NULL THEN
      BEGIN
        v_cid := (NEW.data->>'campaign_id')::uuid;
      EXCEPTION WHEN OTHERS THEN
        v_cid := NULL;
      END;
    END IF;
    IF v_cid IS NOT NULL AND NEW.user_id IS NOT NULL THEN
      UPDATE public.ops_push_receipts
      SET read_at = coalesce(read_at, now())
      WHERE campaign_id = v_cid AND user_id = NEW.user_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ops_push_receipt_on_read ON public.in_app_notifications;
CREATE TRIGGER trg_ops_push_receipt_on_read
  AFTER UPDATE OF is_read ON public.in_app_notifications
  FOR EACH ROW
  EXECUTE FUNCTION public._ops_push_receipt_on_read();

REVOKE ALL ON FUNCTION public.platform_staff_directory(text, int, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_directory(text, int, text) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_team_time() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_team_time() TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_billing_watch() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_billing_watch() TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_upsert_campaign(text, text, text, text, text, text, text, timestamptz, timestamptz, text, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_upsert_campaign(text, text, text, text, text, text, text, timestamptz, timestamptz, text, boolean, text) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_dispatch_campaign(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_dispatch_campaign(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_run_due_campaigns() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_run_due_campaigns() TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_list_campaigns() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_list_campaigns() TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_campaign_receipts(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_campaign_receipts(uuid) TO authenticated;

COMMIT;
