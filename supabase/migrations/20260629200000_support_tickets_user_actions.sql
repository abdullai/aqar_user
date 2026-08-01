-- Support tickets: extended complaint fields + user feedback RPCs (no direct UPDATE on table).

ALTER TABLE public.regc_user_complaints
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'complaint',
  ADD COLUMN IF NOT EXISTS contact_channel text NOT NULL DEFAULT 'in_app',
  ADD COLUMN IF NOT EXISTS details jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.regc_user_complaints.kind IS 'complaint | suggestion';
COMMENT ON COLUMN public.regc_user_complaints.contact_channel IS 'whatsapp | in_app';
COMMENT ON COLUMN public.regc_user_complaints.details IS 'User resolution, rating, admin reply metadata (JSON).';

CREATE OR REPLACE FUNCTION public.support_submit_complaint_v1(
  p_kind text,
  p_subject text,
  p_body text,
  p_contact_channel text,
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_kind text := lower(trim(coalesce(p_kind, 'complaint')));
  v_channel text := lower(trim(coalesce(p_contact_channel, 'in_app')));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF length(trim(coalesce(p_subject, ''))) < 2 THEN
    RAISE EXCEPTION 'subject_required';
  END IF;
  IF length(trim(coalesce(p_body, ''))) < 5 THEN
    RAISE EXCEPTION 'body_required';
  END IF;
  IF v_kind NOT IN ('complaint', 'suggestion') THEN
    v_kind := 'complaint';
  END IF;
  IF v_channel NOT IN ('whatsapp', 'in_app') THEN
    v_channel := 'in_app';
  END IF;

  INSERT INTO public.regc_user_complaints (
    user_id, subject, body, status, kind, contact_channel, details
  )
  VALUES (
    v_uid,
    trim(p_subject),
    trim(p_body),
    'open',
    v_kind,
    v_channel,
    coalesce(p_details, '{}'::jsonb) || jsonb_build_object(
      'user_resolution', 'open',
      'submitted_at', to_jsonb(now())
    )
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.support_complaint_user_feedback_v1(
  p_complaint_id uuid,
  p_action text,
  p_rating int DEFAULT NULL,
  p_feedback text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.regc_user_complaints%ROWTYPE;
  v_action text := lower(trim(coalesce(p_action, '')));
  v_details jsonb;
  v_status text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF p_complaint_id IS NULL THEN
    RAISE EXCEPTION 'invalid_complaint_id';
  END IF;

  SELECT * INTO v_row
  FROM public.regc_user_complaints
  WHERE id = p_complaint_id AND user_id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'complaint_not_found';
  END IF;

  v_details := coalesce(v_row.details, '{}'::jsonb);

  IF v_action = 'resolved' THEN
    v_status := 'resolved';
    v_details := v_details || jsonb_build_object(
      'user_resolution', 'resolved',
      'resolved_at', to_jsonb(now()),
      'rating', p_rating,
      'user_feedback', nullif(trim(coalesce(p_feedback, '')), '')
    );
  ELSIF v_action = 'unresolved' THEN
    v_status := 'open';
    v_details := v_details || jsonb_build_object(
      'user_resolution', 'unresolved',
      'reopened_at', to_jsonb(now())
    );
  ELSIF v_action = 'escalate' THEN
    v_status := 'escalated';
    v_details := v_details || jsonb_build_object(
      'user_resolution', 'escalated',
      'escalated_at', to_jsonb(now())
    );
    INSERT INTO public.regc_complaint_escalations (complaint_id, escalated_to, notes)
    VALUES (
      p_complaint_id,
      'platform_admin',
      coalesce(nullif(trim(coalesce(p_feedback, '')), ''), 'User requested escalation')
    );
  ELSE
    RAISE EXCEPTION 'invalid_action';
  END IF;

  UPDATE public.regc_user_complaints
  SET status = v_status, details = v_details
  WHERE id = p_complaint_id AND user_id = v_uid;
END;
$$;

GRANT EXECUTE ON FUNCTION public.support_submit_complaint_v1(text, text, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.support_complaint_user_feedback_v1(uuid, text, int, text) TO authenticated;
