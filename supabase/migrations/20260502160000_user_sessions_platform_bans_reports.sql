-- جلسات المستخدمين، حظر المنصّة، طلبات تغيير نوع الحساب، موظفو المنصّة
-- متطلبات: pgcrypto لتجزئة IP (لا تُخزَّن عناوين خام)

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ---------------------------------------------------------------------------
-- 1) سجل الدخول/الخروج — user_login_sessions
--    لا نستخدم اسم user_sessions: الجدول القديم (20260410) نموذج مبسّط
--    بأعمدة device / last_active وليس login_at.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_login_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  device_info text,
  browser_info text,
  os_info text,
  ip_hash text,
  location text,
  login_at timestamptz NOT NULL DEFAULT now(),
  logout_at timestamptz,
  session_duration_seconds int,
  is_active boolean NOT NULL DEFAULT true,
  logout_reason text,
  login_method text,
  CONSTRAINT user_login_sessions_logout_reason_chk CHECK (
    logout_reason IS NULL OR logout_reason IN (
      'user_logout', 'session_expired', 'admin_terminated', 'device_revoked', 'unknown'
    )
  )
);

CREATE INDEX IF NOT EXISTS idx_user_login_sessions_user_login
  ON public.user_login_sessions (user_id, login_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_login_sessions_active
  ON public.user_login_sessions (user_id) WHERE is_active = true;

ALTER TABLE public.user_login_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_login_sessions_select_own ON public.user_login_sessions;
CREATE POLICY user_login_sessions_select_own ON public.user_login_sessions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- لا insert/update مباشر من العميل
CREATE OR REPLACE FUNCTION public._user_sessions_ip_hash(p_ip text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, extensions
AS $$
  SELECT encode(
    extensions.digest(
      convert_to(
        coalesce(nullif(trim(p_ip), ''), '-') || '|aqar_user_ip_pepper_v1',
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$$;

CREATE OR REPLACE FUNCTION public.cleanup_old_user_sessions()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.user_login_sessions
  WHERE login_at < now() - interval '90 days';
END;
$$;

CREATE OR REPLACE FUNCTION public.log_user_session_start(
  p_device_info text DEFAULT NULL,
  p_browser_info text DEFAULT NULL,
  p_os_info text DEFAULT NULL,
  p_ip text DEFAULT NULL,
  p_location text DEFAULT NULL,
  p_login_method text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;
  PERFORM public.cleanup_old_user_sessions();
  UPDATE public.user_login_sessions
  SET is_active = false,
      logout_at = coalesce(logout_at, now()),
      logout_reason = coalesce(logout_reason, 'session_expired'),
      session_duration_seconds = coalesce(
        session_duration_seconds,
        greatest(0, extract(epoch from (now() - login_at))::int)
      )
  WHERE user_id = v_uid AND is_active = true;

  INSERT INTO public.user_login_sessions (
    user_id, device_info, browser_info, os_info, ip_hash, location, login_method, is_active
  ) VALUES (
    v_uid,
    nullif(trim(coalesce(p_device_info, '')), ''),
    nullif(trim(coalesce(p_browser_info, '')), ''),
    nullif(trim(coalesce(p_os_info, '')), ''),
    public._user_sessions_ip_hash(coalesce(p_ip, '')),
    nullif(trim(coalesce(p_location, '')), ''),
    nullif(trim(coalesce(p_login_method, '')), ''),
    true
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'session_id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.log_user_session_end(
  p_session_id uuid,
  p_reason text DEFAULT 'user_logout'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;
  IF p_session_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_session');
  END IF;

  UPDATE public.user_login_sessions
  SET
    is_active = false,
    logout_at = now(),
    logout_reason = nullif(trim(coalesce(p_reason, 'user_logout')), ''),
    session_duration_seconds = greatest(
      0,
      extract(epoch from (now() - login_at))::int
    )
  WHERE id = p_session_id AND user_id = v_uid AND is_active = true;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_my_user_sessions(p_limit int DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  lim int := greatest(1, least(coalesce(p_limit, 50), 100));
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(t.r ORDER BY (t.r->>'login_at') DESC)
    FROM (
      SELECT jsonb_build_object(
        'id', s.id,
        'device_info', coalesce(s.device_info, ''),
        'browser_info', coalesce(s.browser_info, ''),
        'os_info', coalesce(s.os_info, ''),
        'location', coalesce(s.location, ''),
        'login_at', s.login_at,
        'logout_at', s.logout_at,
        'session_duration_seconds', s.session_duration_seconds,
        'is_active', s.is_active,
        'logout_reason', coalesce(s.logout_reason, ''),
        'login_method', coalesce(s.login_method, '')
      ) AS r
      FROM public.user_login_sessions s
      WHERE s.user_id = v_uid
      ORDER BY s.login_at DESC
      LIMIT lim
    ) t
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_my_other_sessions(p_keep_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  n int;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;
  UPDATE public.user_login_sessions
  SET
    is_active = false,
    logout_at = now(),
    logout_reason = 'device_revoked',
    session_duration_seconds = greatest(
      0,
      extract(epoch from (now() - login_at))::int
    )
  WHERE user_id = v_uid
    AND is_active = true
    AND id IS DISTINCT FROM p_keep_session_id;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'closed', n);
END;
$$;

GRANT EXECUTE ON FUNCTION public.log_user_session_start(text, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_user_session_end(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_my_user_sessions(int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_my_other_sessions(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2) حظر المنصّة (banned_accounts)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.platform_staff (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.banned_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES auth.users (id) ON DELETE CASCADE,
  banned_by uuid REFERENCES auth.users (id),
  ban_reason text,
  ban_type text NOT NULL DEFAULT 'permanent' CHECK (ban_type IN ('temporary', 'permanent', 'until_date')),
  ban_until date,
  can_join_other_orgs boolean NOT NULL DEFAULT true,
  blocks_app boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  lifted_at timestamptz,
  lifted_by uuid REFERENCES auth.users (id)
);

CREATE INDEX IF NOT EXISTS idx_banned_accounts_user ON public.banned_accounts (user_id) WHERE lifted_at IS NULL;
ALTER TABLE public.banned_accounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS banned_accounts_select_own ON public.banned_accounts;
CREATE POLICY banned_accounts_select_own ON public.banned_accounts
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.is_platform_staff(p_uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM public.platform_staff s WHERE s.user_id = p_uid);
$$;

CREATE OR REPLACE FUNCTION public.get_my_platform_ban()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  r record;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;
  SELECT * INTO r
  FROM public.banned_accounts b
  WHERE b.user_id = v_uid AND b.lifted_at IS NULL
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'ban', null);
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'ban', jsonb_build_object(
      'id', r.id,
      'ban_reason', coalesce(r.ban_reason, ''),
      'ban_type', r.ban_type,
      'ban_until', r.ban_until,
      'can_join_other_orgs', r.can_join_other_orgs,
      'blocks_app', r.blocks_app,
      'created_at', r.created_at
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_ban_user(
  p_user_id uuid,
  p_reason text,
  p_ban_type text DEFAULT 'permanent',
  p_ban_until date DEFAULT NULL,
  p_can_join_other_orgs boolean DEFAULT true,
  p_blocks_app boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_user');
  END IF;

  INSERT INTO public.banned_accounts (
    user_id, banned_by, ban_reason, ban_type, ban_until, can_join_other_orgs, blocks_app
  ) VALUES (
    p_user_id, v_staff, nullif(trim(coalesce(p_reason, '')), ''),
    coalesce(nullif(trim(coalesce(p_ban_type, '')), ''), 'permanent'),
    p_ban_until, coalesce(p_can_join_other_orgs, true), coalesce(p_blocks_app, true)
  )
  ON CONFLICT (user_id) DO UPDATE SET
    banned_by = excluded.banned_by,
    ban_reason = excluded.ban_reason,
    ban_type = excluded.ban_type,
    ban_until = excluded.ban_until,
    can_join_other_orgs = excluded.can_join_other_orgs,
    blocks_app = excluded.blocks_app,
    lifted_at = NULL,
    lifted_by = NULL,
    created_at = now();

  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_lift_ban(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  UPDATE public.banned_accounts
  SET lifted_at = now(), lifted_by = v_staff
  WHERE user_id = p_user_id AND lifted_at IS NULL;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- محاولات انضمام يومية للمستخدم المعرقل (حد أقصى 3 منشآت مختلفة / يوم)
CREATE TABLE IF NOT EXISTS public.banned_user_org_join_day (
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  day date NOT NULL DEFAULT (timezone('utc', now()))::date,
  org_ids uuid[] NOT NULL DEFAULT '{}',
  PRIMARY KEY (user_id, day)
);

CREATE OR REPLACE FUNCTION public.banned_user_record_org_join_attempt(p_org_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_day date := (timezone('utc', now()))::date;
  ban record;
  arr uuid[];
  new_arr uuid[];
  distinct_cnt int;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;
  SELECT * INTO ban FROM public.banned_accounts b
  WHERE b.user_id = v_uid AND b.lifted_at IS NULL LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'limited', false);
  END IF;
  IF ban.can_join_other_orgs IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'error', 'join_not_allowed');
  END IF;

  SELECT d.org_ids INTO arr
  FROM public.banned_user_org_join_day d
  WHERE d.user_id = v_uid AND d.day = v_day;

  IF arr IS NULL THEN
    new_arr := ARRAY[p_org_id]::uuid[];
  ELSIF arr @> ARRAY[p_org_id]::uuid[] THEN
    new_arr := arr;
  ELSE
    new_arr := arr || p_org_id;
  END IF;

  SELECT count(distinct x) INTO distinct_cnt FROM unnest(new_arr) AS x;
  IF distinct_cnt > 3 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'daily_org_join_limit');
  END IF;

  INSERT INTO public.banned_user_org_join_day (user_id, day, org_ids)
  VALUES (v_uid, v_day, new_arr)
  ON CONFLICT (user_id, day) DO UPDATE
  SET org_ids = excluded.org_ids;

  RETURN jsonb_build_object('ok', true, 'limited', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_platform_ban() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_platform_staff(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_ban_user(uuid, text, text, date, boolean, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_lift_ban(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.banned_user_record_org_join_attempt(uuid) TO authenticated;

-- توسيع تقديم طلب انضمام: التحقق من الحظر وحد المحاولات
CREATE OR REPLACE FUNCTION public.org_submit_join_request_by_org(
  p_org_id uuid,
  p_message text DEFAULT NULL,
  p_verification_request_id bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
  ban record;
  lim jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;
  IF p_org_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_org');
  END IF;

  SELECT * INTO ban FROM public.banned_accounts b
  WHERE b.user_id = v_uid AND b.lifted_at IS NULL LIMIT 1;
  IF FOUND THEN
    IF ban.can_join_other_orgs IS NOT TRUE THEN
      RETURN jsonb_build_object('ok', false, 'error', 'platform_banned_no_join');
    END IF;
    lim := public.banned_user_record_org_join_attempt(p_org_id);
    IF (lim->>'ok')::boolean IS NOT TRUE THEN
      RETURN lim;
    END IF;
  END IF;

  SELECT id INTO v_org FROM org_units WHERE id = p_org_id LIMIT 1;
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_org');
  END IF;

  IF EXISTS (
    SELECT 1 FROM org_banned_users b
    WHERE b.org_id = v_org AND b.user_id = v_uid
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'banned_from_org');
  END IF;

  IF EXISTS (
    SELECT 1 FROM org_memberships m
    WHERE m.user_id = v_uid AND m.status = 'active'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_member');
  END IF;

  IF EXISTS (
    SELECT 1 FROM org_join_requests j
    WHERE j.applicant_user_id = v_uid AND j.status = 'pending'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_pending');
  END IF;

  INSERT INTO org_join_requests (
    org_id,
    applicant_user_id,
    verification_request_id,
    status,
    applicant_message
  ) VALUES (
    v_org,
    v_uid,
    p_verification_request_id,
    'pending',
    nullif(trim(coalesce(p_message, '')), '')
  );

  RETURN jsonb_build_object('ok', true, 'org_id', v_org);
END;
$$;

-- ---------------------------------------------------------------------------
-- 3) طلبات تغيير نوع الحساب
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.account_change_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  current_type text NOT NULL,
  requested_type text NOT NULL,
  current_org_unit_id uuid REFERENCES public.org_units (id),
  requested_organization_code text,
  reason text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_notes text,
  reviewed_by uuid REFERENCES auth.users (id),
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_account_change_user ON public.account_change_requests (user_id, created_at DESC);

ALTER TABLE public.account_change_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS account_change_select_own ON public.account_change_requests;
CREATE POLICY account_change_select_own ON public.account_change_requests
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.submit_account_change_request(
  p_requested_type text,
  p_current_org_unit_id uuid DEFAULT NULL,
  p_requested_organization_code text DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  cur_type text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;
  SELECT coalesce(account_type::text, 'user') INTO cur_type
  FROM public.users_profiles WHERE user_id = v_uid LIMIT 1;

  INSERT INTO public.account_change_requests (
    user_id, current_type, requested_type, current_org_unit_id,
    requested_organization_code, reason, status
  ) VALUES (
    v_uid,
    cur_type,
    nullif(trim(coalesce(p_requested_type, '')), ''),
    p_current_org_unit_id,
    nullif(trim(coalesce(p_requested_organization_code, '')), ''),
    nullif(trim(coalesce(p_reason, '')), ''),
    'pending'
  );
  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_account_change_request(text, uuid, text, text) TO authenticated;

-- إنهاء جميع الجلسات النشطة لمستخدم (موظفو المنصّة فقط)
CREATE OR REPLACE FUNCTION public.platform_staff_terminate_user_sessions(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
  n int;
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_user');
  END IF;
  UPDATE public.user_login_sessions
  SET
    is_active = false,
    logout_at = now(),
    logout_reason = 'admin_terminated',
    session_duration_seconds = greatest(
      0,
      extract(epoch from (now() - login_at))::int
    )
  WHERE user_id = p_user_id AND is_active = true;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'closed', n);
END;
$$;

GRANT EXECUTE ON FUNCTION public.platform_staff_terminate_user_sessions(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4) صلاحية التقارير المتقدمة (view_reports) في القالب الافتراضي
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_default_member_permissions()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'manage_team', false,
    'add_properties', false,
    'add_ads', false,
    'add_listing_requests', false,
    'edit_properties', false,
    'view_market', false,
    'view_profile', true,
    'access_chat', true,
    'edit_org_settings', false,
    'view_analytics', false,
    'view_reports', false,
    'manage_subscription', false,
    'export_data', false,
    'invite_members', false,
    'manage_chat_rooms', false,
    'view_member_activity', false,
    'desk', false,
    'middle_nav', false
  );
$$;

-- توافق مع نمط emergency_security_hardening_phase1: إعادة منح التنفيذ لـ authenticated/service_role
DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'log_user_session_start',
        'log_user_session_end',
        'list_my_user_sessions',
        'revoke_my_other_sessions',
        'get_my_platform_ban',
        'is_platform_staff',
        'platform_staff_ban_user',
        'platform_staff_lift_ban',
        'banned_user_record_org_join_attempt',
        'submit_account_change_request',
        'platform_staff_terminate_user_sessions'
      )
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f.signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f.signature);
  END LOOP;
END $$;

COMMIT;
