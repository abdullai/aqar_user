-- دعم فني: لقطة الاسم الرباعي والجوال عند الرفع، استلام الموظف بالوقت،
-- مرفقات support-uploads، وتصعيد بعد 24 ساعة دون احتساب الترحيب/المسودة رداً.

BEGIN;

-- مرفقات الشكاوى تحت property-images/support-uploads/{uid}/...
DROP POLICY IF EXISTS "support_uploads_insert_own" ON storage.objects;
CREATE POLICY "support_uploads_insert_own"
ON storage.objects
FOR INSERT
TO public
WITH CHECK (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND name ~~ ('support-uploads/' || (auth.uid())::text || '/%')
);

DROP POLICY IF EXISTS "support_uploads_select_own" ON storage.objects;
CREATE POLICY "support_uploads_select_own"
ON storage.objects
FOR SELECT
TO public
USING (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND (
    name ~~ ('support-uploads/' || (auth.uid())::text || '/%')
    OR public.is_platform_staff(auth.uid())
  )
);

CREATE OR REPLACE FUNCTION public._support_local_sa_phone(p_raw text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  d text := regexp_replace(coalesce(p_raw, ''), '\D', '', 'g');
BEGIN
  IF d LIKE '00%' THEN
    d := substr(d, 3);
  END IF;
  IF d LIKE '966%' AND length(d) >= 12 THEN
    d := '0' || substr(d, 4);
  ELSIF length(d) = 9 AND d NOT LIKE '0%' THEN
    d := '0' || d;
  END IF;
  IF length(d) > 10 THEN
    d := right(d, 10);
  END IF;
  RETURN d;
END;
$$;

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
  v_name text;
  v_phone text;
  v_merged jsonb;
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

  v_name := coalesce(
    nullif(trim(coalesce(p_details->>'submitter_name', p_details->>'requester_name', '')), ''),
    public._ops_profile_display_name(v_uid)
  );
  v_phone := public._support_local_sa_phone(
    coalesce(
      nullif(trim(coalesce(p_details->>'submitter_phone', p_details->>'requester_phone', '')), ''),
      (SELECT up.phone FROM public.users_profiles up WHERE up.user_id = v_uid LIMIT 1)
    )
  );

  v_merged := coalesce(p_details, '{}'::jsonb) || jsonb_build_object(
    'user_resolution', 'open',
    'submitted_at', to_jsonb(now()),
    'submitter_name', v_name,
    'requester_name', v_name,
    'submitter_phone', v_phone,
    'requester_phone', v_phone
  );

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
    v_merged
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_open_ticket(p_complaint_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
  r public.regc_user_complaints%ROWTYPE;
  v_staff_name text;
  v_req text;
  v_thread jsonb;
  v_ar text;
  v_en text;
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  SELECT * INTO r FROM public.regc_user_complaints WHERE id = p_complaint_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  IF coalesce(r.details->>'staff_welcomed', '') = 'true' THEN
    RETURN jsonb_build_object('ok', true, 'already', true);
  END IF;
  v_staff_name := public._ops_profile_display_name(v_staff);
  v_req := coalesce(
    nullif(trim(r.details->>'submitter_name'), ''),
    nullif(trim(r.details->>'requester_name'), ''),
    public._ops_profile_display_name(r.user_id)
  );
  v_ar := 'مرحباً ' || v_req || '، معك ' || v_staff_name || ' من دعم المنصة. كيف نقدر نخدمك؟';
  v_en := 'Hello ' || v_req || ', this is ' || v_staff_name || ' from platform support. How can we help you?';
  v_thread := coalesce(r.details->'chat_thread', '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'role', 'staff',
      'kind', 'welcome',
      'text', v_ar,
      'text_en', v_en,
      'at', now(),
      'by', v_staff,
      'staff_name', v_staff_name
    )
  );
  UPDATE public.regc_user_complaints
  SET details = coalesce(details, '{}'::jsonb) || jsonb_build_object(
    'chat_thread', v_thread,
    'staff_welcomed', 'true',
    'assigned_to', v_staff,
    'assigned_name', v_staff_name,
    'received_by_name', v_staff_name,
    'received_at', to_jsonb(now())
  )
  WHERE id = p_complaint_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_reply_complaint(
  p_complaint_id uuid,
  p_reply text,
  p_status text DEFAULT 'awaiting_user'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
  v_reply text := trim(coalesce(p_reply, ''));
  v_status text := lower(trim(coalesce(p_status, 'awaiting_user')));
  r public.regc_user_complaints%ROWTYPE;
  v_thread jsonb;
  v_staff_name text;
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT coalesce((SELECT s.can_support FROM public.platform_staff s WHERE s.user_id = v_staff), true) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_support');
  END IF;
  IF length(v_reply) < 2 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reply_required');
  END IF;
  IF v_status NOT IN ('open', 'awaiting_user', 'escalated', 'resolved', 'closed') THEN
    v_status := 'awaiting_user';
  END IF;

  SELECT * INTO r FROM public.regc_user_complaints WHERE id = p_complaint_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  v_staff_name := public._ops_profile_display_name(v_staff);
  IF coalesce(r.details->>'staff_welcomed', '') IS DISTINCT FROM 'true' THEN
    PERFORM public.platform_staff_open_ticket(p_complaint_id);
    SELECT * INTO r FROM public.regc_user_complaints WHERE id = p_complaint_id;
  END IF;

  v_thread := coalesce(r.details->'chat_thread', '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'role', 'staff',
      'text', v_reply,
      'at', now(),
      'by', v_staff,
      'staff_name', v_staff_name
    )
  );

  UPDATE public.regc_user_complaints
  SET
    status = v_status,
    details = coalesce(details, '{}'::jsonb) || jsonb_build_object(
      'admin_reply', v_reply,
      'admin_reply_at', to_jsonb(now()),
      'admin_reply_by', v_staff,
      'admin_reply_by_name', v_staff_name,
      'assigned_name', v_staff_name,
      'received_by_name', coalesce(nullif(trim(r.details->>'received_by_name'), ''), v_staff_name),
      'received_at', coalesce(r.details->'received_at', to_jsonb(now())),
      'chat_thread', v_thread,
      'solution_summary', CASE WHEN v_status IN ('resolved', 'closed') THEN v_reply ELSE r.details->>'solution_summary' END,
      'resolved_by', CASE WHEN v_status IN ('resolved', 'closed') THEN v_staff_name ELSE r.details->>'resolved_by' END
    )
  WHERE id = p_complaint_id;

  PERFORM public._staff_audit(
    CASE WHEN v_status IN ('resolved', 'closed') THEN 'support_closed' ELSE 'support_reply' END,
    'regc_user_complaints',
    p_complaint_id::text,
    jsonb_build_object('status', v_status, 'staff', v_staff_name)
  );

  BEGIN
    PERFORM public.workflow_create_notification(
      r.user_id,
      'support_ticket',
      CASE WHEN v_status IN ('resolved', 'closed')
        THEN 'تم إغلاق تذكرة الدعم'
        ELSE 'رد على تذكرة الدعم'
      END,
      v_reply,
      'complaint',
      p_complaint_id,
      jsonb_build_object(
        'title_ar', CASE WHEN v_status IN ('resolved', 'closed')
          THEN 'تم حل تذكرتك — ' || v_staff_name
          ELSE 'رد من ' || v_staff_name
        END,
        'title_en', CASE WHEN v_status IN ('resolved', 'closed')
          THEN 'Your ticket was resolved — ' || v_staff_name
          ELSE 'Reply from ' || v_staff_name
        END,
        'body_ar', v_reply,
        'body_en', v_reply
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object('ok', true);
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
  v_has_staff boolean := false;
  v_staff_text text;
  v_elem jsonb;
  v_txt text;
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
  IF v_staff_text IS NOT NULL
     AND v_staff_text NOT LIKE 'مسودة للموظف%'
     AND v_staff_text NOT LIKE 'مسودة:%'
     AND lower(v_staff_text) NOT LIKE 'staff draft%'
     AND lower(v_staff_text) NOT LIKE 'draft:%' THEN
    v_has_staff := true;
  ELSE
    FOR v_elem IN
      SELECT e FROM jsonb_array_elements(coalesce(v_details->'chat_thread', '[]'::jsonb)) AS e
    LOOP
      v_txt := nullif(trim(coalesce(v_elem->>'text', '')), '');
      IF lower(trim(coalesce(v_elem->>'role', ''))) = 'staff'
         AND v_txt IS NOT NULL
         AND coalesce(v_elem->>'kind', '') IS DISTINCT FROM 'welcome'
         AND v_txt NOT LIKE 'مسودة للموظف%'
         AND v_txt NOT LIKE 'مسودة:%'
         AND v_txt NOT LIKE '%من دعم المنصة%كيف نقدر نخدمك%' THEN
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

-- لقطة للجوال/الاسم على التذاكر القديمة إن نقصت.
UPDATE public.regc_user_complaints c
SET details = coalesce(c.details, '{}'::jsonb) || jsonb_build_object(
  'submitter_name', coalesce(
    nullif(trim(c.details->>'submitter_name'), ''),
    nullif(trim(c.details->>'requester_name'), ''),
    public._ops_profile_display_name(c.user_id)
  ),
  'submitter_phone', coalesce(
    nullif(trim(c.details->>'submitter_phone'), ''),
    public._support_local_sa_phone(
      (SELECT up.phone FROM public.users_profiles up WHERE up.user_id = c.user_id LIMIT 1)
    )
  )
)
WHERE coalesce(c.details->>'submitter_phone', '') = ''
   OR coalesce(c.details->>'submitter_name', '') = '';

GRANT EXECUTE ON FUNCTION public._support_local_sa_phone(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.support_submit_complaint_v1(text, text, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.support_complaint_user_feedback_v1(uuid, text, int, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_open_ticket(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_reply_complaint(uuid, text, text) TO authenticated;

COMMIT;
