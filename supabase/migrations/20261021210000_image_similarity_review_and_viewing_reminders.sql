-- 1) كشف تشابه صور الإعلانات (مراجعة بشرية بدل الحجب التلقائي)
-- 2) مراجعة البلاغات قبل إخفاء الإعلان
-- 3) تذكير تلقائي قبل موعد المعاينة

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) بصمات الصور الإدراكية (dHash 64-bit) + تعليمات المراجعة
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.listing_image_hashes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL,
  property_id uuid,
  request_id uuid,
  phash bit(64) NOT NULL,
  sha256 text,
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);
CREATE INDEX IF NOT EXISTS idx_listing_image_hashes_owner
  ON public.listing_image_hashes (owner_id);
CREATE INDEX IF NOT EXISTS idx_listing_image_hashes_created
  ON public.listing_image_hashes (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_listing_image_hashes_sha
  ON public.listing_image_hashes (sha256) WHERE sha256 IS NOT NULL;
ALTER TABLE public.listing_image_hashes ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.listing_image_similarity_flags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL,
  property_id uuid,
  request_id uuid,
  matched_owner_id uuid NOT NULL,
  matched_property_id uuid,
  matched_images integer NOT NULL,
  exact_images integer NOT NULL DEFAULT 0,
  min_distance integer NOT NULL,
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'dismissed', 'confirmed')),
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  reviewed_by uuid,
  reviewed_at timestamptz,
  review_note text
);
CREATE INDEX IF NOT EXISTS idx_image_flags_status
  ON public.listing_image_similarity_flags (status, created_at DESC);
ALTER TABLE public.listing_image_similarity_flags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS listing_image_flags_staff ON public.listing_image_similarity_flags;
CREATE POLICY listing_image_flags_staff ON public.listing_image_similarity_flags
  FOR SELECT TO authenticated
  USING (public.is_platform_staff(auth.uid()));

ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS report_staff_hidden boolean NOT NULL DEFAULT false;

-- p_hashes: [{"p":"<16 hex dHash>","s":"<sha256 اختياري>"}, ...]
CREATE OR REPLACE FUNCTION public.register_listing_image_hashes(
  p_hashes jsonb,
  p_property_id uuid DEFAULT NULL,
  p_request_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_total integer;
  v_flags integer := 0;
  v_key uuid := coalesce(p_property_id, p_request_id);
  m record;
  v_min integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF p_hashes IS NULL OR jsonb_typeof(p_hashes) <> 'array'
     OR jsonb_array_length(p_hashes) = 0 OR jsonb_array_length(p_hashes) > 30 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_hashes');
  END IF;
  IF p_property_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.properties p
    WHERE p.id = p_property_id AND nullif(to_jsonb(p) ->> 'owner_id', '')::uuid = v_uid
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_owner');
  END IF;

  IF v_key IS NOT NULL THEN
    DELETE FROM public.listing_image_hashes
    WHERE owner_id = v_uid AND coalesce(property_id, request_id) = v_key;
  END IF;

  CREATE TEMP TABLE IF NOT EXISTS _new_hashes (
    phash bit(64), sha text
  ) ON COMMIT DROP;
  DELETE FROM _new_hashes;

  INSERT INTO _new_hashes (phash, sha)
  SELECT ('x' || lower(e ->> 'p'))::bit(64),
         nullif(lower(coalesce(e ->> 's', '')), '')
  FROM jsonb_array_elements(p_hashes) e
  WHERE lower(coalesce(e ->> 'p', '')) ~ '^[0-9a-f]{16}$';

  SELECT count(*) INTO v_total FROM _new_hashes;
  IF v_total = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_hashes');
  END IF;

  FOR m IN
    SELECT h.owner_id AS m_owner,
           (array_agg(h.property_id) FILTER (WHERE h.property_id IS NOT NULL))[1] AS m_property,
           count(DISTINCT n.phash) AS matched,
           count(DISTINCT n.phash) FILTER (WHERE h.sha256 IS NOT NULL AND h.sha256 = n.sha) AS exact,
           min(bit_count(h.phash # n.phash))::int AS dist
    FROM (
      SELECT * FROM public.listing_image_hashes
      WHERE owner_id <> v_uid
      ORDER BY created_at DESC
      LIMIT 50000
    ) h
    JOIN _new_hashes n
      ON bit_count(h.phash # n.phash) <= 5
      OR (h.sha256 IS NOT NULL AND h.sha256 = n.sha)
    GROUP BY h.owner_id
  LOOP
    -- صورة واحدة مشتركة لا تكفي لإعلان متعدد الصور (صور عامة/مخزّنة).
    CONTINUE WHEN m.matched < least(2, v_total) AND m.exact = 0;

    IF NOT EXISTS (
      SELECT 1 FROM public.listing_image_similarity_flags f
      WHERE f.owner_id = v_uid AND f.matched_owner_id = m.m_owner
        AND coalesce(f.property_id, f.request_id) IS NOT DISTINCT FROM v_key
        AND f.status = 'open'
    ) THEN
      INSERT INTO public.listing_image_similarity_flags (
        owner_id, property_id, request_id, matched_owner_id, matched_property_id,
        matched_images, exact_images, min_distance
      ) VALUES (
        v_uid, p_property_id, p_request_id, m.m_owner, m.m_property,
        m.matched, m.exact, m.dist
      );
      v_flags := v_flags + 1;
    END IF;
  END LOOP;

  INSERT INTO public.listing_image_hashes (
    owner_id, property_id, request_id, phash, sha256
  )
  SELECT v_uid, p_property_id, p_request_id, phash, sha FROM _new_hashes;

  IF v_flags > 0 THEN
    PERFORM public._viewing_notify(
      v_uid, 'listing_image_review', 'مراجعة صور الإعلان',
      'رصدنا تشابهًا بين بعض صور إعلانك وإعلان آخر. سيراجع فريقنا الحالة، ولا يتأثر نشر إعلانك الآن. إن كانت الصور لك فلا إجراء مطلوب منك.',
      p_property_id, NULL
    );
  END IF;

  RETURN jsonb_build_object('ok', true, 'registered', v_total, 'flagged', v_flags > 0);
END;
$$;

REVOKE ALL ON FUNCTION public.register_listing_image_hashes(jsonb, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_listing_image_hashes(jsonb, uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.platform_staff_list_image_flags(p_limit int DEFAULT 80)
RETURNS SETOF public.listing_image_similarity_flags
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT * FROM public.listing_image_similarity_flags
  WHERE status = 'open'
  ORDER BY exact_images DESC, created_at DESC
  LIMIT greatest(1, least(coalesce(p_limit, 80), 200));
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_review_image_flag(
  p_flag_id uuid,
  p_decision text,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
  v_dec text := lower(trim(coalesce(p_decision, '')));
  f public.listing_image_similarity_flags%ROWTYPE;
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT coalesce((SELECT s.can_moderate FROM public.platform_staff s WHERE s.user_id = v_staff), true) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_moderate');
  END IF;
  IF v_dec NOT IN ('dismissed', 'confirmed') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_decision');
  END IF;
  SELECT * INTO f FROM public.listing_image_similarity_flags
  WHERE id = p_flag_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  UPDATE public.listing_image_similarity_flags
  SET status = v_dec, reviewed_by = v_staff, reviewed_at = now(),
      review_note = nullif(left(trim(coalesce(p_note, '')), 500), '')
  WHERE id = p_flag_id;

  IF v_dec = 'confirmed' AND f.property_id IS NOT NULL THEN
    UPDATE public.properties
    SET report_staff_hidden = true, home_feed_suppressed = true
    WHERE id = f.property_id;
    PERFORM public._viewing_notify(
      f.owner_id, 'listing_image_review', 'إيقاف عرض الإعلان مؤقتًا',
      'بعد المراجعة، أُوقف عرض إعلانك مؤقتًا بسبب تطابق صوره مع إعلان آخر. تواصل مع الدعم لإثبات ملكية الصور.',
      f.property_id, NULL
    );
  END IF;

  PERFORM public._staff_audit(
    'listing_image_flag_review', 'listing_image_similarity_flags', p_flag_id::text,
    jsonb_build_object('decision', v_dec)
  );
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.platform_staff_list_image_flags(int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.platform_staff_review_image_flag(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_list_image_flags(int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_review_image_flag(uuid, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2) البلاغات: 3 مبلّغين = مراجعة + إشعار المعلن؛ الإخفاء بقرار الموظف
--    أو عند 6 مبلّغين مختلفين (صمام أمان ضد موجة احتيال).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.refresh_listing_report_aggregate_for_property(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  distinct_count integer;
  should_suppress boolean;
  v_staff_hidden boolean;
  v_owner uuid;
  v_had_open boolean;
BEGIN
  IF p_property_id IS NULL THEN
    RETURN;
  END IF;

  SELECT count(distinct r.reporter_user_id) INTO distinct_count
  FROM public.listing_user_reports r
  WHERE r.property_id = p_property_id
    AND r.reporter_user_id IS NOT NULL
    AND r.status IN ('pending', 'reviewing')
    AND r.created_at > (now() - interval '7 days');

  SELECT coalesce(p.report_staff_hidden, false),
         nullif(to_jsonb(p) ->> 'owner_id', '')::uuid
  INTO v_staff_hidden, v_owner
  FROM public.properties p WHERE p.id = p_property_id;

  should_suppress := coalesce(distinct_count, 0) >= 6 OR coalesce(v_staff_hidden, false);

  UPDATE public.properties p
  SET
    report_distinct_reporters_7d = coalesce(distinct_count, 0),
    home_feed_suppressed = should_suppress,
    report_escalated_at = CASE
      WHEN coalesce(distinct_count, 0) >= 3 THEN coalesce(p.report_escalated_at, now())
      ELSE p.report_escalated_at
    END
  WHERE p.id = p_property_id;

  IF coalesce(distinct_count, 0) >= 3 THEN
    SELECT EXISTS (
      SELECT 1 FROM public.listing_moderation_escalations e
      WHERE e.property_id = p_property_id AND e.status = 'open'
    ) INTO v_had_open;

    INSERT INTO public.listing_moderation_escalations (
      property_id, distinct_reporters_7d, status, first_escalated_at, updated_at
    ) VALUES (
      p_property_id, coalesce(distinct_count, 0), 'open', now(), now()
    )
    ON CONFLICT (property_id) DO UPDATE SET
      distinct_reporters_7d = excluded.distinct_reporters_7d,
      status = 'open',
      updated_at = now();

    IF NOT v_had_open AND v_owner IS NOT NULL THEN
      PERFORM public._viewing_notify(
        v_owner, 'listing_under_review', 'إعلانك قيد المراجعة',
        'وصلتنا بلاغات على أحد إعلاناتك، وسيراجعها فريقنا قبل أي إجراء. إعلانك ما زال معروضًا أثناء المراجعة.',
        p_property_id, NULL
      );
    END IF;
  END IF;
END;
$$;

-- قرار الموظف النهائي على الإعلان المُصعَّد: إخفاء أو إبقاء.
CREATE OR REPLACE FUNCTION public.platform_staff_resolve_listing_escalation(
  p_property_id uuid,
  p_hide boolean,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
  v_owner uuid;
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT coalesce((SELECT s.can_moderate FROM public.platform_staff s WHERE s.user_id = v_staff), true) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_moderate');
  END IF;

  SELECT nullif(to_jsonb(p) ->> 'owner_id', '')::uuid INTO v_owner
  FROM public.properties p WHERE p.id = p_property_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  UPDATE public.properties
  SET report_staff_hidden = coalesce(p_hide, false),
      home_feed_suppressed = coalesce(p_hide, false)
  WHERE id = p_property_id;

  UPDATE public.listing_moderation_escalations
  SET status = 'resolved', updated_at = now()
  WHERE property_id = p_property_id;

  IF coalesce(p_hide, false) AND v_owner IS NOT NULL THEN
    PERFORM public._viewing_notify(
      v_owner, 'listing_under_review', 'إيقاف عرض الإعلان مؤقتًا',
      'بعد مراجعة البلاغات أُوقف عرض أحد إعلاناتك مؤقتًا. راجع صفحة الإعلان أو تواصل مع الدعم.',
      p_property_id, NULL
    );
  END IF;

  PERFORM public._staff_audit(
    'listing_escalation_resolve', 'properties', p_property_id::text,
    jsonb_build_object('hide', coalesce(p_hide, false), 'note', left(coalesce(p_note, ''), 300))
  );
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.platform_staff_resolve_listing_escalation(uuid, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_resolve_listing_escalation(uuid, boolean, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) تذكيرات المعاينة (قبل الموعد بـ 24 ساعة)
-- ---------------------------------------------------------------------------
ALTER TABLE public.property_viewing_requests
  ADD COLUMN IF NOT EXISTS reminder_requester_at timestamptz,
  ADD COLUMN IF NOT EXISTS reminder_owner_at timestamptz;

CREATE OR REPLACE FUNCTION public._viewing_send_reminders(p_user uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_n integer := 0;
  v_hours integer;
  v_body text;
BEGIN
  FOR r IN
    SELECT * FROM public.property_viewing_requests
    WHERE status = 'confirmed'
      AND confirmed_at > now()
      AND confirmed_at <= now() + interval '24 hours'
      AND (
        (reminder_requester_at IS NULL AND (p_user IS NULL OR requester_id = p_user))
        OR (reminder_owner_at IS NULL AND (p_user IS NULL OR owner_id = p_user))
      )
    LIMIT 200
  LOOP
    v_hours := greatest(1, ceil(extract(epoch FROM (r.confirmed_at - now())) / 3600.0)::int);
    v_body := 'موعد المعاينة بعد نحو ' || v_hours || ' ساعة: '
      || public._viewing_fmt(r.confirmed_at);

    IF r.reminder_requester_at IS NULL AND (p_user IS NULL OR r.requester_id = p_user) THEN
      UPDATE public.property_viewing_requests
      SET reminder_requester_at = now() WHERE id = r.id;
      PERFORM public._viewing_notify(
        r.requester_id, 'viewing_reminder', 'تذكير بموعد المعاينة',
        v_body, r.property_id, r.id);
      v_n := v_n + 1;
    END IF;
    IF r.reminder_owner_at IS NULL AND (p_user IS NULL OR r.owner_id = p_user) THEN
      UPDATE public.property_viewing_requests
      SET reminder_owner_at = now() WHERE id = r.id;
      PERFORM public._viewing_notify(
        r.owner_id, 'viewing_reminder', 'تذكير بموعد المعاينة',
        v_body, r.property_id, r.id);
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION public.send_due_viewing_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN 0;
  END IF;
  RETURN public._viewing_send_reminders(auth.uid());
END;
$$;

REVOKE ALL ON FUNCTION public._viewing_send_reminders(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.send_due_viewing_reminders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_due_viewing_reminders() TO authenticated;

-- جدولة دورية عند توفر pg_cron؛ وإلا يعمل التذكير عند فتح التطبيق.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'aqar_viewing_reminders',
      '*/15 * * * *',
      'SELECT public._viewing_send_reminders(NULL)'
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron schedule skipped: %', SQLERRM;
END;
$$;

COMMIT;
