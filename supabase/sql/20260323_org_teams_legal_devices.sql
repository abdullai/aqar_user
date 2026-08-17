-- =============================================================================
-- فرق العمل للمكاتب / المؤسسات / الشركات العقارية + شروط قانونية + أجهزة (حدّ 2)
-- نفّذ في Supabase SQL Editor بعد المراجعة. يضيف جداول وأعمدة بـ IF NOT EXISTS حيث ينطبق.
-- =============================================================================
-- مهم: طابق نمط البريد في Edge Function org_invite_member مع دالة get_email_by_national_id
-- لديك (مثال شائع: {national_id}@your-domain.internal).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) أعمدة users_profiles
-- ---------------------------------------------------------------------------
ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS org_id uuid;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS terms_version_accepted text;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS terms_accepted_at timestamptz;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS primary_device_registered_at timestamptz;

COMMENT ON COLUMN public.users_profiles.org_id IS 'Organization unit for office/institution/company team';
COMMENT ON COLUMN public.users_profiles.must_change_password IS 'Team invite: force password change on first login';
COMMENT ON COLUMN public.users_profiles.terms_version_accepted IS 'Last accepted legal_documents_versions.version';

-- ---------------------------------------------------------------------------
-- 2) org_units
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.org_units (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL UNIQUE REFERENCES auth.users (id) ON DELETE CASCADE,
  account_type text NOT NULL CHECK (account_type IN ('office', 'institution', 'company')),
  base_seat_limit int NOT NULL CHECK (base_seat_limit > 0),
  purchased_extra_seats int NOT NULL DEFAULT 0 CHECK (purchased_extra_seats >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_org_units_account_type ON public.org_units (account_type);

-- ---------------------------------------------------------------------------
-- 3) org_memberships (مستخدم واحد = مؤسسة واحدة كحد أقصى)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.org_memberships (
  org_id uuid NOT NULL REFERENCES public.org_units (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  member_role text NOT NULL CHECK (member_role IN ('owner', 'member')),
  permissions jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
  invited_by_user_id uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (org_id, user_id),
  CONSTRAINT org_memberships_user_unique UNIQUE (user_id)
);

CREATE INDEX IF NOT EXISTS idx_org_memberships_org ON public.org_memberships (org_id);
CREATE INDEX IF NOT EXISTS idx_org_memberships_user ON public.org_memberships (user_id);

-- FK من users_profiles.org_id (بعد إنشاء org_units)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'users_profiles_org_id_fkey'
  ) THEN
    ALTER TABLE public.users_profiles
      ADD CONSTRAINT users_profiles_org_id_fkey
      FOREIGN KEY (org_id) REFERENCES public.org_units (id) ON DELETE SET NULL;
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ---------------------------------------------------------------------------
-- 4) legal_documents_versions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.legal_documents_versions (
  version text PRIMARY KEY,
  title_ar text NOT NULL,
  title_en text NOT NULL,
  body_ar text NOT NULL,
  body_en text NOT NULL,
  effective_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_legal_effective ON public.legal_documents_versions (effective_at DESC);

-- ---------------------------------------------------------------------------
-- 5) org_activity_log
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.org_activity_log (
  id bigserial PRIMARY KEY,
  org_id uuid NOT NULL REFERENCES public.org_units (id) ON DELETE CASCADE,
  actor_user_id uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  action text NOT NULL,
  entity_type text,
  entity_id text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_org_activity_org_time ON public.org_activity_log (org_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_org_activity_actor ON public.org_activity_log (actor_user_id);

-- ---------------------------------------------------------------------------
-- 6) user_trusted_devices (حدّ جهازين نشطين لكل مستخدم)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_trusted_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  device_fingerprint text NOT NULL,
  platform text,
  model_label text,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_trusted_devices_active_fp
  ON public.user_trusted_devices (user_id, device_fingerprint)
  WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_user_trusted_devices_user_active
  ON public.user_trusted_devices (user_id)
  WHERE revoked_at IS NULL;

-- ---------------------------------------------------------------------------
-- 7) دوال مساعدة
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.org_effective_seat_limit(p_org_id uuid)
RETURNS int
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT base_seat_limit + purchased_extra_seats
  FROM org_units
  WHERE id = p_org_id;
$$;

CREATE OR REPLACE FUNCTION public.org_current_member_count(p_org_id uuid)
RETURNS int
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT count(*)::int
  FROM org_memberships
  WHERE org_id = p_org_id AND status = 'active';
$$;

-- إنشاء مؤسسة للمستخدم الحالي إن كان office/institution/company وليس لديه سجل بعد
CREATE OR REPLACE FUNCTION public.ensure_my_org_unit()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_type text;
  v_org uuid;
  v_limit int;
BEGIN
  IF v_uid IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT lower(trim(account_type::text)) INTO v_type
  FROM users_profiles
  WHERE user_id = v_uid;

  IF v_type IS NULL OR v_type NOT IN ('office', 'institution', 'company') THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_org FROM org_units WHERE owner_user_id = v_uid LIMIT 1;
  IF v_org IS NOT NULL THEN
    UPDATE users_profiles SET org_id = v_org WHERE user_id = v_uid AND (org_id IS DISTINCT FROM v_org);
    RETURN v_org;
  END IF;

  v_limit := CASE v_type
    WHEN 'office' THEN 3
    WHEN 'institution' THEN 8
    ELSE 12
  END;

  INSERT INTO org_units (owner_user_id, account_type, base_seat_limit)
  VALUES (v_uid, v_type, v_limit)
  RETURNING id INTO v_org;

  INSERT INTO org_memberships (org_id, user_id, member_role, permissions, status)
  VALUES (v_org, v_uid, 'owner', '{"all": true}'::jsonb, 'active');

  UPDATE users_profiles SET org_id = v_org WHERE user_id = v_uid;

  RETURN v_org;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_active_legal_version()
RETURNS TABLE (
  version text,
  title_ar text,
  title_en text,
  body_ar text,
  body_en text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT l.version, l.title_ar, l.title_en, l.body_ar, l.body_en
  FROM legal_documents_versions l
  WHERE l.effective_at <= now()
  ORDER BY l.effective_at DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.accept_terms_v1(p_version text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF p_version IS NULL OR length(trim(p_version)) = 0 THEN
    RAISE EXCEPTION 'invalid_version';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM legal_documents_versions WHERE version = trim(p_version)) THEN
    RAISE EXCEPTION 'unknown_version';
  END IF;
  UPDATE users_profiles
  SET terms_version_accepted = trim(p_version),
      terms_accepted_at = now()
  WHERE user_id = v_uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_must_change_password_after_auth()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  UPDATE users_profiles
  SET must_change_password = false
  WHERE user_id = v_uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.register_user_device_v2(
  p_device_id text,
  p_platform text DEFAULT NULL,
  p_model_label text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_count int;
  v_existing uuid;
  fp text := trim(coalesce(p_device_id, ''));
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;
  IF length(fp) < 4 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_device');
  END IF;

  SELECT id INTO v_existing
  FROM user_trusted_devices
  WHERE user_id = v_uid AND device_fingerprint = fp AND revoked_at IS NULL;

  IF v_existing IS NOT NULL THEN
    UPDATE user_trusted_devices
    SET
      last_seen_at = now(),
      platform = coalesce(nullif(trim(coalesce(p_platform, '')), ''), platform),
      model_label = coalesce(nullif(trim(coalesce(p_model_label, '')), ''), model_label)
    WHERE id = v_existing;

    UPDATE users_profiles
    SET primary_device_registered_at = coalesce(primary_device_registered_at, now())
    WHERE user_id = v_uid;

    RETURN jsonb_build_object('ok', true, 'registered', false);
  END IF;

  SELECT count(*)::int INTO v_count
  FROM user_trusted_devices
  WHERE user_id = v_uid AND revoked_at IS NULL;

  IF v_count >= 2 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'device_limit');
  END IF;

  INSERT INTO user_trusted_devices (user_id, device_fingerprint, platform, model_label)
  VALUES (
    v_uid,
    fp,
    nullif(trim(coalesce(p_platform, '')), ''),
    nullif(trim(coalesce(p_model_label, '')), '')
  );

  UPDATE users_profiles
  SET primary_device_registered_at = coalesce(primary_device_registered_at, now())
  WHERE user_id = v_uid;

  RETURN jsonb_build_object('ok', true, 'registered', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_my_trusted_device(p_device_fingerprint text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  fp text := trim(coalesce(p_device_fingerprint, ''));
BEGIN
  IF v_uid IS NULL OR length(fp) < 4 THEN
    RETURN false;
  END IF;
  UPDATE user_trusted_devices
  SET revoked_at = now()
  WHERE user_id = v_uid AND device_fingerprint = fp AND revoked_at IS NULL;
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_org_activity(
  p_org_id uuid,
  p_action text,
  p_entity_type text DEFAULT NULL,
  p_entity_id text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_org_id IS NULL OR p_action IS NULL OR length(trim(p_action)) = 0 THEN
    RETURN;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM org_memberships m
    WHERE m.org_id = p_org_id AND m.user_id = v_uid AND m.status = 'active'
  ) THEN
    RETURN;
  END IF;
  INSERT INTO org_activity_log (org_id, actor_user_id, action, entity_type, entity_id, metadata)
  VALUES (
    p_org_id,
    v_uid,
    trim(p_action),
    nullif(trim(coalesce(p_entity_type, '')), ''),
    nullif(trim(coalesce(p_entity_id, '')), ''),
    coalesce(p_metadata, '{}'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.my_org_context()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_owner uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('org_id', null, 'member_role', null, 'is_owner', false);
  END IF;

  SELECT m.org_id, m.member_role INTO v_org, v_role
  FROM org_memberships m
  WHERE m.user_id = v_uid AND m.status = 'active'
  LIMIT 1;

  IF v_org IS NULL THEN
    RETURN jsonb_build_object('org_id', null, 'member_role', null, 'is_owner', false);
  END IF;

  SELECT owner_user_id INTO v_owner FROM org_units WHERE id = v_org LIMIT 1;

  RETURN jsonb_build_object(
    'org_id', v_org,
    'member_role', v_role,
    'is_owner', (v_owner = v_uid)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.org_update_member_permissions(
  p_member_user_id uuid,
  p_permissions jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  SELECT id INTO v_org FROM org_units WHERE owner_user_id = v_uid LIMIT 1;
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'not_org_owner';
  END IF;
  IF p_member_user_id = v_uid THEN
    RAISE EXCEPTION 'cannot_change_owner_permissions';
  END IF;
  UPDATE org_memberships
  SET permissions = coalesce(p_permissions, '{}'::jsonb)
  WHERE org_id = v_org AND user_id = p_member_user_id AND member_role = 'member';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'member_not_found';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.org_owner_revoke_member_device(
  p_member_user_id uuid,
  p_device_fingerprint text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
  fp text := trim(coalesce(p_device_fingerprint, ''));
BEGIN
  IF v_uid IS NULL OR length(fp) < 4 THEN
    RETURN false;
  END IF;
  SELECT id INTO v_org FROM org_units WHERE owner_user_id = v_uid LIMIT 1;
  IF v_org IS NULL THEN
    RETURN false;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM org_memberships m
    WHERE m.org_id = v_org AND m.user_id = p_member_user_id AND m.status = 'active'
  ) THEN
    RETURN false;
  END IF;
  UPDATE user_trusted_devices
  SET revoked_at = now()
  WHERE user_id = p_member_user_id AND device_fingerprint = fp AND revoked_at IS NULL;
  RETURN FOUND;
END;
$$;

-- ---------------------------------------------------------------------------
-- 8) RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.org_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_trusted_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_documents_versions ENABLE ROW LEVEL SECURITY;

-- org_units
DROP POLICY IF EXISTS org_units_select_member ON public.org_units;
CREATE POLICY org_units_select_member ON public.org_units
  FOR SELECT TO authenticated
  USING (
    owner_user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM org_memberships m
      WHERE m.org_id = org_units.id AND m.user_id = auth.uid() AND m.status = 'active'
    )
  );

-- org_memberships
DROP POLICY IF EXISTS org_memberships_select ON public.org_memberships;
CREATE POLICY org_memberships_select ON public.org_memberships
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM org_units o
      WHERE o.id = org_memberships.org_id AND o.owner_user_id = auth.uid()
    )
  );

-- org_activity_log
DROP POLICY IF EXISTS org_activity_log_select ON public.org_activity_log;
CREATE POLICY org_activity_log_select ON public.org_activity_log
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM org_units o
      WHERE o.id = org_activity_log.org_id AND o.owner_user_id = auth.uid()
    )
    OR actor_user_id = auth.uid()
  );

-- user_trusted_devices
DROP POLICY IF EXISTS utd_select_own ON public.user_trusted_devices;
CREATE POLICY utd_select_own ON public.user_trusted_devices
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS utd_select_org_owner ON public.user_trusted_devices;
CREATE POLICY utd_select_org_owner ON public.user_trusted_devices
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM org_units o
      JOIN org_memberships m ON m.org_id = o.id AND m.user_id = user_trusted_devices.user_id
      WHERE o.owner_user_id = auth.uid() AND m.status = 'active'
    )
  );

DROP POLICY IF EXISTS utd_update_own_revoke ON public.user_trusted_devices;
CREATE POLICY utd_update_own_revoke ON public.user_trusted_devices
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- legal: قراءة للمستخدمين المسجلين
DROP POLICY IF EXISTS legal_read_auth ON public.legal_documents_versions;
CREATE POLICY legal_read_auth ON public.legal_documents_versions
  FOR SELECT TO authenticated
  USING (true);

-- ---------------------------------------------------------------------------
-- 9) صلاحيات التنفيذ
-- ---------------------------------------------------------------------------
GRANT SELECT ON public.legal_documents_versions TO authenticated;
GRANT SELECT ON public.org_units TO authenticated;
GRANT SELECT ON public.org_memberships TO authenticated;
GRANT SELECT ON public.org_activity_log TO authenticated;
GRANT SELECT ON public.user_trusted_devices TO authenticated;

GRANT EXECUTE ON FUNCTION public.org_effective_seat_limit(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_current_member_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_my_org_unit() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_active_legal_version() TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_terms_v1(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.clear_must_change_password_after_auth() TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_user_device_v2(text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_my_trusted_device(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_org_activity(uuid, text, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_org_context() TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_update_member_permissions(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_owner_revoke_member_device(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 10) بذرة نسخة شروط (يمكن تعديل النص لاحقاً)
-- ---------------------------------------------------------------------------
INSERT INTO public.legal_documents_versions (version, title_ar, title_en, body_ar, body_en, effective_at)
VALUES (
  '2026-03-01',
  'الشروط والأحكام',
  'Terms and Conditions',
  'باستخدامك للتطبيق فإنك توافق على الالتزام بالأنظمة المعمول بها في المملكة العربية السعودية، وعلى استخدام المنصة وفق الغرض المخصص لها، وعلى صحة البيانات التي تقدمها. يحق للمنصة تعليق أو إنهاء الوصول عند مخالفة الشروط.',
  'By using this application you agree to comply with applicable laws in the Kingdom of Saudi Arabia, to use the platform for its intended purpose, and to provide accurate information. The platform may suspend or terminate access for violations.',
  timestamptz '2026-01-01 00:00:00+00'
)
ON CONFLICT (version) DO NOTHING;
