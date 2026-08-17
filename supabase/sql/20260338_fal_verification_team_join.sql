-- =============================================================================
-- رخصة فال (لقطة REGA) + رقم تعريف عام 10 أرقام + رمز انضمام فريق العمل + طلبات الانضمام
-- نفّذ في Supabase SQL Editor بعد المراجعة.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) أعمدة users_profiles
-- ---------------------------------------------------------------------------
ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS public_member_id text;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS contact_email text;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS contact_phone text;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS rega_fal_snapshot jsonb;

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_profiles_public_member_id
  ON public.users_profiles (public_member_id)
  WHERE public_member_id IS NOT NULL AND length(trim(public_member_id)) > 0;

COMMENT ON COLUMN public.users_profiles.public_member_id IS
  'معرّف عام مكوّن من 10 أرقام (يُولَّد تلقائياً). يُمنح لموظفين المنشأة كـ«رمز انضمام» سرّي.';

-- ---------------------------------------------------------------------------
-- 2) verification_requests.extra_payload
-- ---------------------------------------------------------------------------
ALTER TABLE public.verification_requests
  ADD COLUMN IF NOT EXISTS extra_payload jsonb;

-- ---------------------------------------------------------------------------
-- 3) org_units.recruit_join_code
-- ---------------------------------------------------------------------------
ALTER TABLE public.org_units
  ADD COLUMN IF NOT EXISTS recruit_join_code text;

CREATE UNIQUE INDEX IF NOT EXISTS uq_org_units_recruit_join_code
  ON public.org_units (recruit_join_code)
  WHERE recruit_join_code IS NOT NULL AND length(trim(recruit_join_code)) > 0;

-- ---------------------------------------------------------------------------
-- 4) توليد أرقام فريدة 10 خانات
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.gen_unique_public_member_id()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  t text;
  n int := 0;
BEGIN
  LOOP
    t := lpad((floor(random() * 10000000000)::bigint)::text, 10, '0');
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.users_profiles WHERE public_member_id = t
    );
    n := n + 1;
    IF n > 80 THEN
      RAISE EXCEPTION 'could not allocate public_member_id';
    END IF;
  END LOOP;
  RETURN t;
END;
$$;

CREATE OR REPLACE FUNCTION public.gen_unique_recruit_join_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  t text;
  n int := 0;
BEGIN
  LOOP
    t := lpad((floor(random() * 10000000000)::bigint)::text, 10, '0');
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.org_units WHERE recruit_join_code = t
    );
    n := n + 1;
    IF n > 80 THEN
      RAISE EXCEPTION 'could not allocate recruit_join_code';
    END IF;
  END LOOP;
  RETURN t;
END;
$$;

CREATE OR REPLACE FUNCTION public.users_profiles_assign_public_member_id()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.public_member_id IS NULL OR length(trim(NEW.public_member_id)) = 0 THEN
    NEW.public_member_id := public.gen_unique_public_member_id();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_users_profiles_public_member_id ON public.users_profiles;
CREATE TRIGGER tr_users_profiles_public_member_id
  BEFORE INSERT ON public.users_profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.users_profiles_assign_public_member_id();

CREATE OR REPLACE FUNCTION public.org_units_assign_recruit_join_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.recruit_join_code IS NULL OR length(trim(NEW.recruit_join_code)) < 10 THEN
    NEW.recruit_join_code := public.gen_unique_recruit_join_code();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_org_units_recruit_join_code ON public.org_units;
CREATE TRIGGER tr_org_units_recruit_join_code
  BEFORE INSERT ON public.org_units
  FOR EACH ROW
  EXECUTE FUNCTION public.org_units_assign_recruit_join_code();

-- تعبئة سجلات قديمة بلا رمز
UPDATE public.org_units ou
SET recruit_join_code = public.gen_unique_recruit_join_code()
WHERE ou.recruit_join_code IS NULL OR length(trim(ou.recruit_join_code)) < 10;

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT user_id
    FROM public.users_profiles
    WHERE public_member_id IS NULL OR length(trim(public_member_id)) = 0
  LOOP
    UPDATE public.users_profiles
    SET public_member_id = public.gen_unique_public_member_id()
    WHERE user_id = r.user_id;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 5) org_join_requests
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.org_join_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.org_units (id) ON DELETE CASCADE,
  applicant_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  verification_request_id bigint REFERENCES public.verification_requests (id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  decided_by_user_id uuid REFERENCES auth.users (id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_org_join_requests_org_status
  ON public.org_join_requests (org_id, status);

CREATE INDEX IF NOT EXISTS idx_org_join_requests_applicant
  ON public.org_join_requests (applicant_user_id);

ALTER TABLE public.org_join_requests ENABLE ROW LEVEL SECURITY;

-- القراءة: صاحب الطلب أو مالك المنشأة
CREATE POLICY org_join_requests_select_own
  ON public.org_join_requests
  FOR SELECT
  USING (
    applicant_user_id = auth.uid()
    OR EXISTS (
      SELECT 1
      FROM public.org_units o
      WHERE o.id = org_join_requests.org_id
        AND o.owner_user_id = auth.uid()
    )
  );

-- الإدراج عبر RPC (SECURITY DEFINER) غالباً؛ نسمح للمستخدم بإدراج صفّه فقط إن لزم الاستدعاء المباشر
CREATE POLICY org_join_requests_insert_applicant
  ON public.org_join_requests
  FOR INSERT
  WITH CHECK (applicant_user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 6) RPC: رمز الانضمام للمالك
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_get_my_recruit_join_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
  v_code text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT id, recruit_join_code INTO v_org, v_code
  FROM public.org_units
  WHERE owner_user_id = v_uid
  LIMIT 1;

  IF v_org IS NULL THEN
    RETURN NULL;
  END IF;

  IF v_code IS NULL OR length(trim(v_code)) < 10 THEN
    v_code := public.gen_unique_recruit_join_code();
    UPDATE public.org_units SET recruit_join_code = v_code WHERE id = v_org;
  END IF;

  RETURN v_code;
END;
$$;

-- ---------------------------------------------------------------------------
-- 7) RPC: تقديم طلب انضمام (بعد التوثيق)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_submit_join_request(
  p_recruit_code text,
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
  v_code text := regexp_replace(trim(coalesce(p_recruit_code, '')), '\D', '', 'g');
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;
  IF length(v_code) != 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_code');
  END IF;

  SELECT id INTO v_org FROM public.org_units WHERE recruit_join_code = v_code LIMIT 1;
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_code');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.org_memberships
    WHERE user_id = v_uid AND status = 'active'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_member');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.org_join_requests
    WHERE applicant_user_id = v_uid AND status = 'pending'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_pending');
  END IF;

  INSERT INTO public.org_join_requests (
    org_id,
    applicant_user_id,
    status,
    verification_request_id
  )
  VALUES (v_org, v_uid, 'pending', p_verification_request_id);

  RETURN jsonb_build_object('ok', true, 'org_id', v_org);
END;
$$;

-- ---------------------------------------------------------------------------
-- 8) RPC: قائمة الطلبات المعلّقة (للمالك)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_list_pending_join_requests()
RETURNS TABLE (
  request_id uuid,
  applicant_user_id uuid,
  created_at timestamptz,
  verification_request_id bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  SELECT id INTO v_org FROM public.org_units WHERE owner_user_id = v_uid LIMIT 1;
  IF v_org IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT j.id, j.applicant_user_id, j.created_at, j.verification_request_id
  FROM public.org_join_requests j
  WHERE j.org_id = v_org AND j.status = 'pending'
  ORDER BY j.created_at ASC;
END;
$$;

-- ---------------------------------------------------------------------------
-- 9) RPC: موافقة / رفض انضمام
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_decide_join_request(
  p_request_id uuid,
  p_approve boolean,
  p_permissions jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_org uuid;
  v_req public.org_join_requests%ROWTYPE;
  v_lim int;
  v_cnt int;
BEGIN
  IF v_owner IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;

  SELECT * INTO v_req FROM public.org_join_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  IF v_req.status IS DISTINCT FROM 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_pending');
  END IF;

  SELECT id INTO v_org
  FROM public.org_units
  WHERE id = v_req.org_id AND owner_user_id = v_owner
  LIMIT 1;

  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_owner');
  END IF;

  IF NOT p_approve THEN
    UPDATE public.org_join_requests
    SET
      status = 'rejected',
      decided_at = now(),
      decided_by_user_id = v_owner
    WHERE id = p_request_id;
    RETURN jsonb_build_object('ok', true, 'approved', false);
  END IF;

  v_lim := public.org_effective_seat_limit(v_org);
  v_cnt := public.org_current_member_count(v_org);
  IF v_cnt >= v_lim THEN
    RETURN jsonb_build_object('ok', false, 'error', 'seat_limit_reached');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.org_memberships WHERE user_id = v_req.applicant_user_id
  ) THEN
    UPDATE public.org_join_requests
    SET
      status = 'rejected',
      decided_at = now(),
      decided_by_user_id = v_owner
    WHERE id = p_request_id;
    RETURN jsonb_build_object('ok', false, 'error', 'already_member_conflict');
  END IF;

  INSERT INTO public.org_memberships (
    org_id,
    user_id,
    member_role,
    permissions,
    status,
    invited_by_user_id
  )
  VALUES (
    v_org,
    v_req.applicant_user_id,
    'member',
    coalesce(p_permissions, '{}'::jsonb),
    'active',
    v_owner
  );

  UPDATE public.users_profiles
  SET org_id = v_org
  WHERE user_id = v_req.applicant_user_id;

  UPDATE public.org_join_requests
  SET
    status = 'approved',
    decided_at = now(),
    decided_by_user_id = v_owner
  WHERE id = p_request_id;

  RETURN jsonb_build_object('ok', true, 'approved', true);
END;
$$;

-- صلاحيات التنفيذ للمستخدمين المسجّلين (PostgREST)
GRANT EXECUTE ON FUNCTION public.org_get_my_recruit_join_code() TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_submit_join_request(text, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_list_pending_join_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_decide_join_request(uuid, boolean, jsonb) TO authenticated;
