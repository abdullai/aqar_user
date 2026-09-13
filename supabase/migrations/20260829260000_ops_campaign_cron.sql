-- جدولة حملات بدون فتح اللوحة (pg_cron إن وُجد) + إرسال داخلي بدون جلسة موظف.
-- نفّذ بعد نجاح 20260829250000.

BEGIN;

CREATE OR REPLACE FUNCTION public._ops_dispatch_campaign_core(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c public.ops_push_campaigns%ROWTYPE;
  r record;
  v_n int := 0;
  v_q text;
  v_batch int;
  v_last uuid;
BEGIN
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
    status = CASE WHEN v_n < v_batch THEN 'sent' ELSE 'sending' END
  WHERE id = p_id;

  RETURN jsonb_build_object(
    'ok', true,
    'sent', v_n,
    'status', CASE WHEN v_n < v_batch THEN 'sent' ELSE 'sending' END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_dispatch_campaign(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  RETURN public._ops_dispatch_campaign_core(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public._ops_run_due_campaigns_core()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_n int := 0;
BEGIN
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
    PERFORM public._ops_dispatch_campaign_core(r.id);
    v_n := v_n + 1;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'ran', v_n);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_run_due_campaigns()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  RETURN public._ops_run_due_campaigns_core();
END;
$$;

CREATE OR REPLACE FUNCTION public.cron_ops_run_due_campaigns()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public._ops_run_due_campaigns_core();
END;
$$;

REVOKE ALL ON FUNCTION public._ops_dispatch_campaign_core(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._ops_run_due_campaigns_core() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cron_ops_run_due_campaigns() FROM PUBLIC;

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
  PERFORM cron.unschedule('ops_due_campaigns');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.schedule(
    'ops_due_campaigns',
    '* * * * *',
    $job$SELECT public.cron_ops_run_due_campaigns();$job$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron not enabled on this project: %', SQLERRM;
END $$;

COMMIT;
