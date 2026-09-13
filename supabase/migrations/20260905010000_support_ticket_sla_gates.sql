-- Support tickets: escalate only after SLA; unresolved only after a staff reply.

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
  v_has_staff boolean := false;
  v_staff_text text;
  v_elem jsonb;
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
  v_staff_text := nullif(trim(coalesce(v_details->>'admin_reply', '')), '');
  IF v_staff_text IS NOT NULL THEN
    v_has_staff := true;
  ELSE
    FOR v_elem IN
      SELECT e FROM jsonb_array_elements(coalesce(v_details->'chat_thread', '[]'::jsonb)) AS e
    LOOP
      IF lower(trim(coalesce(v_elem->>'role', ''))) = 'staff'
         AND length(trim(coalesce(v_elem->>'text', ''))) > 0 THEN
        v_has_staff := true;
        EXIT;
      END IF;
    END LOOP;
  END IF;

  IF v_action = 'resolved' THEN
    IF NOT v_has_staff THEN
      RAISE EXCEPTION 'staff_reply_required';
    END IF;
    v_status := 'resolved';
    v_details := v_details || jsonb_build_object(
      'user_resolution', 'resolved',
      'resolved_at', to_jsonb(now()),
      'rating', p_rating,
      'user_feedback', nullif(trim(coalesce(p_feedback, '')), '')
    );
  ELSIF v_action = 'unresolved' THEN
    IF NOT v_has_staff THEN
      RAISE EXCEPTION 'staff_reply_required';
    END IF;
    IF lower(trim(coalesce(v_row.status, ''))) IN ('resolved', 'closed')
       AND lower(trim(coalesce(v_details->>'user_resolution', ''))) = 'resolved' THEN
      RAISE EXCEPTION 'already_resolved';
    END IF;
    v_status := 'open';
    v_details := v_details || jsonb_build_object(
      'user_resolution', 'unresolved',
      'reopened_at', to_jsonb(now())
    );
  ELSIF v_action = 'escalate' THEN
    IF lower(trim(coalesce(v_row.status, ''))) IN ('resolved', 'closed') THEN
      RAISE EXCEPTION 'already_resolved';
    END IF;
    IF lower(trim(coalesce(v_row.status, ''))) = 'escalated' THEN
      RAISE EXCEPTION 'already_escalated';
    END IF;
    IF v_row.created_at IS NULL OR now() < (v_row.created_at + interval '24 hours') THEN
      RAISE EXCEPTION 'sla_not_elapsed';
    END IF;
    v_status := 'escalated';
    v_details := v_details || jsonb_build_object(
      'user_resolution', 'escalated',
      'escalated_at', to_jsonb(now())
    );
    INSERT INTO public.regc_complaint_escalations (complaint_id, escalated_to, notes)
    VALUES (
      p_complaint_id,
      'platform_admin',
      coalesce(nullif(trim(coalesce(p_feedback, '')), ''), 'User requested escalation after SLA')
    );
  ELSE
    RAISE EXCEPTION 'invalid_action';
  END IF;

  UPDATE public.regc_user_complaints
  SET status = v_status, details = v_details
  WHERE id = p_complaint_id AND user_id = v_uid;
END;
$$;

GRANT EXECUTE ON FUNCTION public.support_complaint_user_feedback_v1(uuid, text, int, text) TO authenticated;

COMMENT ON FUNCTION public.support_complaint_user_feedback_v1(uuid, text, int, text) IS
  'User ticket feedback: unresolved/resolved require a staff reply; escalate only after 24h and if not resolved.';
