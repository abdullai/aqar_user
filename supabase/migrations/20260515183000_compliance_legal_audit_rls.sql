-- =============================================================================
-- Compliance: legal policy versioning, acceptances, audit, complaints, consent.
-- RLS: anon may SELECT active regc_legal_policy_documents only; no anon on sensitive.
-- Client writes: authenticated EXECUTE on RPCs + own complaints/consent_preferences.
--
-- In-app complaints use public.regc_user_complaints (NOT legacy public.complaints):
-- many projects already have a legacy "complaints" table without user_id; IF NOT EXISTS
-- would skip CREATE and later statements would error with 42703.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.regc_legal_policy_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  policy_type text NOT NULL CHECK (policy_type IN (
    'privacy_policy', 'terms_of_use', 'cookies_policy', 'intellectual_property'
  )),
  language text NOT NULL CHECK (language IN ('ar', 'en')),
  version text NOT NULL,
  content text NOT NULL,
  effective_date timestamptz NOT NULL DEFAULT now(),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT legal_policy_documents_version_unique UNIQUE (policy_type, language, version)
);

CREATE UNIQUE INDEX IF NOT EXISTS legal_policy_documents_one_active_per_lang_type
  ON public.regc_legal_policy_documents (policy_type, language)
  WHERE active;

CREATE TABLE IF NOT EXISTS public.regc_user_legal_acceptances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  policy_id uuid NOT NULL REFERENCES public.regc_legal_policy_documents (id) ON DELETE RESTRICT,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  ip_address inet,
  user_agent text,
  consent_type text NOT NULL DEFAULT 'terms'
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_legal_acceptance_user_policy
  ON public.regc_user_legal_acceptances (user_id, policy_id);

CREATE INDEX IF NOT EXISTS idx_user_legal_acceptances_user ON public.regc_user_legal_acceptances (user_id);

CREATE TABLE IF NOT EXISTS public.regc_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  event_type text NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_compliance_audit_user_time
  ON public.regc_audit_logs (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_compliance_audit_event
  ON public.regc_audit_logs (event_type);

CREATE TABLE IF NOT EXISTS public.regc_incidents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  severity text NOT NULL DEFAULT 'medium',
  status text NOT NULL DEFAULT 'open',
  description text NOT NULL,
  reported_by uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.regc_user_complaints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  subject text NOT NULL,
  body text NOT NULL,
  status text NOT NULL DEFAULT 'open',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_compliance_user_complaints_user
  ON public.regc_user_complaints (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.regc_complaint_escalations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  complaint_id uuid NOT NULL REFERENCES public.regc_user_complaints (id) ON DELETE CASCADE,
  escalated_to text NOT NULL,
  escalated_at timestamptz NOT NULL DEFAULT now(),
  notes text
);

CREATE INDEX IF NOT EXISTS idx_compliance_complaint_escalations_complaint
  ON public.regc_complaint_escalations (complaint_id);

CREATE TABLE IF NOT EXISTS public.regc_security_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users (id) ON DELETE CASCADE,
  action text NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_security_events_user_time
  ON public.regc_security_events (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.regc_consent_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  analytics_cookies boolean NOT NULL DEFAULT false,
  marketing_cookies boolean NOT NULL DEFAULT false,
  essential_ack boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.regc_legal_policy_documents IS 'Versioned legal/policy text; one active row per policy_type+language.';
COMMENT ON TABLE public.regc_user_legal_acceptances IS 'Per-user acceptance of a specific regc_legal_policy_documents row.';
COMMENT ON TABLE public.regc_audit_logs IS 'Append-only audit trail; insert via compliance_append_audit RPC.';
COMMENT ON TABLE public.regc_user_complaints IS 'In-app complaint intake; escalations in regc_complaint_escalations.';

-- -----------------------------------------------------------------------------
-- RPC: append compliance audit (authenticated caller only)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.compliance_append_audit(
  p_event_type text,
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
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF p_event_type IS NULL OR length(trim(p_event_type)) = 0 THEN
    RAISE EXCEPTION 'invalid_event_type';
  END IF;
  INSERT INTO public.regc_audit_logs (user_id, event_type, metadata)
  VALUES (v_uid, trim(p_event_type), coalesce(p_metadata, '{}'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.append_security_event_v1(
  p_action text,
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
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF p_action IS NULL OR length(trim(p_action)) = 0 THEN
    RAISE EXCEPTION 'invalid_action';
  END IF;
  INSERT INTO public.regc_security_events (user_id, action, metadata)
  VALUES (v_uid, trim(p_action), coalesce(p_metadata, '{}'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_consent_preferences_v1(
  p_analytics boolean,
  p_marketing boolean,
  p_essential_ack boolean DEFAULT true
)
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
  INSERT INTO public.regc_consent_preferences (user_id, analytics_cookies, marketing_cookies, essential_ack, updated_at)
  VALUES (v_uid, p_analytics, p_marketing, coalesce(p_essential_ack, true), now())
  ON CONFLICT (user_id) DO UPDATE SET
    analytics_cookies = excluded.analytics_cookies,
    marketing_cookies = excluded.marketing_cookies,
    essential_ack = excluded.essential_ack,
    updated_at = now();
  PERFORM public.compliance_append_audit(
    'consent.preferences_updated',
    jsonb_build_object(
      'analytics_cookies', p_analytics,
      'marketing_cookies', p_marketing,
      'essential_ack', coalesce(p_essential_ack, true)
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.record_legal_acceptances_after_terms_v1(
  p_version text,
  p_lang text,
  p_user_agent text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_lang text := lower(trim(coalesce(p_lang, 'ar')));
  v_ver text := trim(coalesce(p_version, ''));
  v_policy text;
  v_pid uuid;
  v_consent text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF length(v_ver) = 0 THEN
    RAISE EXCEPTION 'invalid_version';
  END IF;
  IF v_lang NOT IN ('ar', 'en') THEN
    v_lang := 'ar';
  END IF;

  FOREACH v_policy IN ARRAY ARRAY['terms_of_use', 'cookies_policy']::text[]
  LOOP
    SELECT l.id INTO v_pid
    FROM public.regc_legal_policy_documents l
    WHERE l.policy_type = v_policy
      AND l.language = v_lang
      AND l.version = v_ver
      AND l.active
    LIMIT 1;

    IF v_pid IS NULL THEN
      CONTINUE;
    END IF;

    v_consent := CASE WHEN v_policy = 'cookies_policy' THEN 'cookies' ELSE 'terms' END;

    INSERT INTO public.regc_user_legal_acceptances (user_id, policy_id, user_agent, consent_type)
    VALUES (v_uid, v_pid, nullif(trim(coalesce(p_user_agent, '')), ''), v_consent)
    ON CONFLICT (user_id, policy_id) DO UPDATE SET
      accepted_at = excluded.accepted_at,
      user_agent = coalesce(excluded.user_agent, public.regc_user_legal_acceptances.user_agent),
      consent_type = excluded.consent_type;
  END LOOP;

  INSERT INTO public.regc_consent_preferences (user_id, analytics_cookies, marketing_cookies, essential_ack, updated_at)
  VALUES (v_uid, false, false, true, now())
  ON CONFLICT (user_id) DO UPDATE SET
    essential_ack = true,
    updated_at = now();

  PERFORM public.compliance_append_audit(
    'terms.accepted',
    jsonb_build_object('version', v_ver, 'lang', v_lang)
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------

ALTER TABLE public.regc_legal_policy_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regc_user_legal_acceptances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regc_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regc_incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regc_user_complaints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regc_complaint_escalations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regc_security_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regc_consent_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS legal_policy_documents_read_active ON public.regc_legal_policy_documents;
CREATE POLICY legal_policy_documents_read_active ON public.regc_legal_policy_documents
  FOR SELECT TO anon, authenticated
  USING (active = true);

DROP POLICY IF EXISTS user_legal_acceptances_select_own ON public.regc_user_legal_acceptances;
CREATE POLICY user_legal_acceptances_select_own ON public.regc_user_legal_acceptances
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS compliance_audit_logs_select_own ON public.regc_audit_logs;
CREATE POLICY compliance_audit_logs_select_own ON public.regc_audit_logs
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS compliance_incidents_select_own ON public.regc_incidents;
CREATE POLICY compliance_incidents_select_own ON public.regc_incidents
  FOR SELECT TO authenticated
  USING (reported_by = auth.uid());

DROP POLICY IF EXISTS compliance_incidents_insert_reporter ON public.regc_incidents;
CREATE POLICY compliance_incidents_insert_reporter ON public.regc_incidents
  FOR INSERT TO authenticated
  WITH CHECK (reported_by = auth.uid());

DROP POLICY IF EXISTS complaints_select_own ON public.regc_user_complaints;
CREATE POLICY complaints_select_own ON public.regc_user_complaints
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS complaints_insert_own ON public.regc_user_complaints;
CREATE POLICY complaints_insert_own ON public.regc_user_complaints
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS complaint_escalations_select_via_complaint ON public.regc_complaint_escalations;
CREATE POLICY complaint_escalations_select_via_complaint ON public.regc_complaint_escalations
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.regc_user_complaints c
      WHERE c.id = complaint_id AND c.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS complaint_escalations_insert_own_complaint ON public.regc_complaint_escalations;
CREATE POLICY complaint_escalations_insert_own_complaint ON public.regc_complaint_escalations
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.regc_user_complaints c
      WHERE c.id = complaint_id AND c.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS security_events_select_own ON public.regc_security_events;
CREATE POLICY security_events_select_own ON public.regc_security_events
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS consent_preferences_select_own ON public.regc_consent_preferences;
CREATE POLICY consent_preferences_select_own ON public.regc_consent_preferences
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS consent_preferences_insert_own ON public.regc_consent_preferences;
CREATE POLICY consent_preferences_insert_own ON public.regc_consent_preferences
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS consent_preferences_update_own ON public.regc_consent_preferences;
CREATE POLICY consent_preferences_update_own ON public.regc_consent_preferences
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- Grants (explicit; anon has no write on sensitive tables)
-- -----------------------------------------------------------------------------

GRANT SELECT ON public.regc_legal_policy_documents TO anon, authenticated;
GRANT SELECT ON public.regc_user_legal_acceptances TO authenticated;
GRANT SELECT ON public.regc_audit_logs TO authenticated;
GRANT SELECT ON public.regc_incidents TO authenticated;
GRANT INSERT ON public.regc_incidents TO authenticated;
GRANT SELECT, INSERT ON public.regc_user_complaints TO authenticated;
GRANT SELECT, INSERT ON public.regc_complaint_escalations TO authenticated;
GRANT SELECT ON public.regc_security_events TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.regc_consent_preferences TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON public.regc_legal_policy_documents FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.regc_user_legal_acceptances FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.regc_audit_logs FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.regc_incidents FROM anon;
REVOKE UPDATE, DELETE ON public.regc_incidents FROM authenticated;
REVOKE UPDATE, DELETE ON public.regc_user_complaints FROM anon, authenticated;
REVOKE UPDATE, DELETE ON public.regc_complaint_escalations FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.regc_security_events FROM anon, authenticated;

GRANT EXECUTE ON FUNCTION public.compliance_append_audit(text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.append_security_event_v1(text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_consent_preferences_v1(boolean, boolean, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_legal_acceptances_after_terms_v1(text, text, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- Seed active policies (aligned with legal_documents_versions gate version)
-- -----------------------------------------------------------------------------

INSERT INTO public.regc_legal_policy_documents (policy_type, language, version, content, effective_date, active)
VALUES
  (
    'privacy_policy', 'ar', '2026-04-05-SA',
    'سياسة الخصوصية (نسخة مرجعية 2026). تفاصيل كاملة في مستودع المشروع: docs/compliance/PRIVACY_POLICY_AR.md — يجب مراجعة محامٍ قبل الإنتاج.',
    now(), true
  ),
  (
    'privacy_policy', 'en', '2026-04-05-SA',
    'Privacy Policy (reference 2026). Full text in repo: docs/compliance/PRIVACY_POLICY_EN.md — legal review required before production.',
    now(), true
  ),
  (
    'terms_of_use', 'ar', '2026-04-05-SA',
    'شروط الاستخدام (نسخة مرجعية 2026). نص كامل: docs/compliance/TERMS_OF_USE_AR.md — يُكمّل عرض الشروط النشطة في legal_documents_versions.',
    now(), true
  ),
  (
    'terms_of_use', 'en', '2026-04-05-SA',
    'Terms of Use (reference 2026). Full text: docs/compliance/TERMS_OF_USE_EN.md — complements active row in legal_documents_versions.',
    now(), true
  ),
  (
    'cookies_policy', 'ar', '2026-04-05-SA',
    'سياسة الكوكيز (مرجعية). نص كامل: docs/compliance/COOKIES_POLICY_AR.md',
    now(), true
  ),
  (
    'cookies_policy', 'en', '2026-04-05-SA',
    'Cookies policy (reference). Full text: docs/compliance/COOKIES_POLICY_EN.md',
    now(), true
  ),
  (
    'intellectual_property', 'ar', '2026-04-05-SA',
    'سياسة الملكية الفكرية (مرجعية). نص كامل: docs/compliance/INTELLECTUAL_PROPERTY_AR.md',
    now(), true
  ),
  (
    'intellectual_property', 'en', '2026-04-05-SA',
    'Intellectual property policy (reference). Full text: docs/compliance/INTELLECTUAL_PROPERTY_EN.md',
    now(), true
  )
ON CONFLICT (policy_type, language, version) DO NOTHING;
