-- عمليات البحث المحفوظة + تنبيهات المطابقة داخل التطبيق + طلبات معاينة العقار.
-- لا دفع ولا توثيق رسمي هنا؛ كل التنبيهات تُدرج في in_app_notifications.

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) تطبيع عربي بسيط للمقارنة (ألف/تاء مربوطة/ياء/تشكيل)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.aqar_norm_ar(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(
    regexp_replace(
      translate(coalesce(p, ''), 'أإآةىـ', 'اااهي '),
      '[\u064B-\u065F]', '', 'g'
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- 1) البحث المحفوظ
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.saved_property_searches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  query_text text NOT NULL DEFAULT '' CHECK (char_length(query_text) <= 200),
  property_type text CHECK (property_type IN ('villa', 'apartment', 'land')),
  purpose text CHECK (purpose IN ('sale', 'rent', 'auction', 'investment')),
  price_min numeric CHECK (price_min IS NULL OR price_min >= 0),
  price_max numeric CHECK (price_max IS NULL OR price_max >= 0),
  bedrooms_min integer CHECK (bedrooms_min IS NULL OR bedrooms_min BETWEEN 0 AND 30),
  keywords text[] NOT NULL DEFAULT '{}',
  notify boolean NOT NULL DEFAULT true,
  last_matched_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS idx_saved_property_searches_user
  ON public.saved_property_searches (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_saved_property_searches_notify
  ON public.saved_property_searches (property_type, purpose)
  WHERE notify;

ALTER TABLE public.saved_property_searches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS saved_property_searches_select_own ON public.saved_property_searches;
CREATE POLICY saved_property_searches_select_own
  ON public.saved_property_searches FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS saved_property_searches_insert_own ON public.saved_property_searches;
CREATE POLICY saved_property_searches_insert_own
  ON public.saved_property_searches FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS saved_property_searches_update_own ON public.saved_property_searches;
CREATE POLICY saved_property_searches_update_own
  ON public.saved_property_searches FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS saved_property_searches_delete_own ON public.saved_property_searches;
CREATE POLICY saved_property_searches_delete_own
  ON public.saved_property_searches FOR DELETE TO authenticated
  USING (user_id = auth.uid());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_property_searches TO authenticated;

-- حد أقصى 20 بحثاً لكل مستخدم + تنظيف المدخلات.
CREATE OR REPLACE FUNCTION public.saved_property_searches_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF (SELECT count(*) FROM public.saved_property_searches WHERE user_id = NEW.user_id) >= 20 THEN
      RAISE EXCEPTION 'saved_search_limit_reached' USING ERRCODE = 'P0001';
    END IF;
  END IF;
  NEW.query_text := left(trim(coalesce(NEW.query_text, '')), 200);
  NEW.keywords := coalesce(
    (SELECT array_agg(left(t.k, 40))
     FROM (SELECT k FROM unnest(NEW.keywords) AS k WHERE trim(k) <> '' LIMIT 8) t),
    '{}'
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_saved_property_searches_guard ON public.saved_property_searches;
CREATE TRIGGER trg_saved_property_searches_guard
  BEFORE INSERT OR UPDATE ON public.saved_property_searches
  FOR EACH ROW EXECUTE FUNCTION public.saved_property_searches_guard();

-- منع تكرار التنبيه لنفس (بحث، عقار). لا وصول مباشر من العملاء.
CREATE TABLE IF NOT EXISTS public.saved_search_matches (
  search_id uuid NOT NULL REFERENCES public.saved_property_searches (id) ON DELETE CASCADE,
  property_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  PRIMARY KEY (search_id, property_id)
);
ALTER TABLE public.saved_search_matches ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 2) مطابقة عقار منشور مع عمليات البحث المحفوظة وإشعار أصحابها
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_saved_search_matches()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_public constant text[] := ARRAY[
    'published', 'active', 'available', 'live', 'approved', 'listed',
    'open', 'visible', 'for_sale', 'for_rent', 'forsale', 'forrent'
  ];
  j jsonb := to_jsonb(NEW);
  v_status text := lower(coalesce(j ->> 'status', ''));
  v_type text := lower(coalesce(j ->> 'type', ''));
  v_purpose text := lower(coalesce(j ->> 'purpose', ''));
  v_price numeric := nullif(j ->> 'price', '')::numeric;
  v_beds integer := nullif(j ->> 'bedrooms', '')::integer;
  v_owner uuid := nullif(j ->> 'owner_id', '')::uuid;
  v_hay text;
  v_title text := coalesce(nullif(trim(j ->> 'title'), ''), 'عقار جديد');
  s record;
  v_ok boolean;
  k text;
  v_rows integer;
  v_reason text;
  v_title_ar text;
  v_body_ar text;
  v_username text;
BEGIN
  IF v_status <> ALL (v_public) THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND lower(coalesce(to_jsonb(OLD) ->> 'status', '')) = ANY (v_public) THEN
    RETURN NEW;
  END IF;
  IF coalesce((j ->> 'home_feed_suppressed')::boolean, false) THEN
    RETURN NEW;
  END IF;

  v_hay := public.aqar_norm_ar(concat_ws(' ',
    j ->> 'title', j ->> 'description', j ->> 'city', j ->> 'location',
    j ->> 'address_line', j ->> 'location_text', j ->> 'region',
    j ->> 'governorate', j ->> 'district', j ->> 'neighborhood'
  ));

  FOR s IN
    SELECT *
    FROM public.saved_property_searches
    WHERE notify
      AND (v_owner IS NULL OR user_id <> v_owner)
      AND (property_type IS NULL OR property_type = v_type)
    LIMIT 500
  LOOP
    v_ok := true;

    IF s.purpose IS NOT NULL THEN
      v_ok := CASE s.purpose
        WHEN 'rent' THEN v_purpose LIKE '%rent%'
        WHEN 'auction' THEN v_purpose LIKE '%auction%'
        WHEN 'investment' THEN v_purpose LIKE '%invest%'
        ELSE v_purpose NOT LIKE '%rent%' AND v_purpose NOT LIKE '%auction%'
      END;
    END IF;

    IF v_ok AND s.price_max IS NOT NULL THEN
      v_ok := v_price IS NOT NULL AND v_price <= s.price_max;
    END IF;
    IF v_ok AND s.price_min IS NOT NULL THEN
      v_ok := v_price IS NOT NULL AND v_price >= s.price_min;
    END IF;
    IF v_ok AND s.bedrooms_min IS NOT NULL THEN
      v_ok := v_beds IS NOT NULL AND v_beds >= s.bedrooms_min;
    END IF;

    IF v_ok THEN
      FOREACH k IN ARRAY s.keywords LOOP
        IF position(public.aqar_norm_ar(k) IN v_hay) = 0 THEN
          v_ok := false;
          EXIT;
        END IF;
      END LOOP;
    END IF;

    CONTINUE WHEN NOT v_ok;

    INSERT INTO public.saved_search_matches (search_id, property_id)
    VALUES (s.id, NEW.id)
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    CONTINUE WHEN v_rows = 0;

    UPDATE public.saved_property_searches
    SET last_matched_at = timezone('utc', now())
    WHERE id = s.id;

    v_reason := concat_ws(' · ',
      CASE s.property_type
        WHEN 'villa' THEN 'فيلا' WHEN 'apartment' THEN 'شقة' WHEN 'land' THEN 'أرض'
      END,
      CASE s.purpose
        WHEN 'rent' THEN 'للإيجار' WHEN 'sale' THEN 'للبيع'
        WHEN 'auction' THEN 'مزاد' WHEN 'investment' THEN 'استثمار'
      END,
      CASE WHEN s.price_max IS NOT NULL
        THEN 'ضمن ميزانيتك حتى ' || to_char(s.price_max, 'FM999,999,999,999') END,
      CASE WHEN s.bedrooms_min IS NOT NULL
        THEN s.bedrooms_min::text || '+ غرف' END,
      CASE WHEN array_length(s.keywords, 1) > 0
        THEN array_to_string(s.keywords, ' ') END
    );

    v_title_ar := 'عقار جديد يطابق بحثك';
    v_body_ar := left(v_title, 80)
      || CASE WHEN v_price IS NOT NULL
           THEN ' — ' || to_char(v_price, 'FM999,999,999,999') || ' ر.س' ELSE '' END
      || CASE WHEN v_reason <> '' THEN E'\nسبب الاقتراح: ' || v_reason ELSE '' END
      || E'\nالمطابقة تقديرية بحسب بيانات الإعلان.';

    SELECT username INTO v_username
    FROM public.users_profiles WHERE user_id = s.user_id LIMIT 1;

    INSERT INTO public.in_app_notifications (
      user_id, username, type, title, body, data, created_at, is_read
    ) VALUES (
      s.user_id,
      coalesce(nullif(trim(v_username), ''), s.user_id::text),
      'saved_search_match',
      v_title_ar,
      v_body_ar,
      jsonb_build_object(
        'title_ar', v_title_ar,
        'body_ar', v_body_ar,
        'entity_type', 'property',
        'entity_id', NEW.id,
        'deep_route', 'property_details',
        'preview_property_id', NEW.id,
        'property_id', NEW.id,
        'saved_search_id', s.id,
        'match_reason', v_reason,
        'channel', 'in_app'
      ),
      timezone('utc', now()),
      false
    );
  END LOOP;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- التنبيهات لا يجوز أن تعطّل نشر الإعلان.
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_saved_search_matches() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_notify_saved_search_matches ON public.properties;
CREATE TRIGGER trg_notify_saved_search_matches
  AFTER INSERT OR UPDATE OF status ON public.properties
  FOR EACH ROW EXECUTE FUNCTION public.notify_saved_search_matches();

-- ---------------------------------------------------------------------------
-- 3) طلبات المعاينة
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.property_viewing_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL,
  owner_id uuid NOT NULL,
  requester_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  proposed_at timestamptz NOT NULL,
  counter_at timestamptz,
  confirmed_at timestamptz,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'confirmed', 'counter_proposed', 'declined', 'cancelled')),
  requester_note text CHECK (requester_note IS NULL OR char_length(requester_note) <= 300),
  owner_note text CHECK (owner_note IS NULL OR char_length(owner_note) <= 300),
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS idx_viewing_requests_property
  ON public.property_viewing_requests (property_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_viewing_requests_requester
  ON public.property_viewing_requests (requester_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_viewing_requests_one_active
  ON public.property_viewing_requests (property_id, requester_id)
  WHERE status IN ('pending', 'counter_proposed');

ALTER TABLE public.property_viewing_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS viewing_requests_select_parties ON public.property_viewing_requests;
CREATE POLICY viewing_requests_select_parties
  ON public.property_viewing_requests FOR SELECT TO authenticated
  USING (requester_id = auth.uid() OR owner_id = auth.uid());

GRANT SELECT ON public.property_viewing_requests TO authenticated;

CREATE OR REPLACE FUNCTION public._viewing_notify(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_property_id uuid,
  p_request_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_username text;
BEGIN
  SELECT username INTO v_username
  FROM public.users_profiles WHERE user_id = p_user_id LIMIT 1;

  INSERT INTO public.in_app_notifications (
    user_id, username, type, title, body, data, created_at, is_read
  ) VALUES (
    p_user_id,
    coalesce(nullif(trim(v_username), ''), p_user_id::text),
    p_type,
    p_title,
    p_body,
    jsonb_build_object(
      'title_ar', p_title,
      'body_ar', p_body,
      'entity_type', 'property',
      'entity_id', p_property_id,
      'deep_route', 'property_details',
      'preview_property_id', p_property_id,
      'property_id', p_property_id,
      'viewing_request_id', p_request_id,
      'channel', 'in_app'
    ),
    timezone('utc', now()),
    false
  );
END;
$$;
REVOKE ALL ON FUNCTION public._viewing_notify(uuid, text, text, text, uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public._viewing_fmt(p_ts timestamptz)
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT to_char(p_ts AT TIME ZONE 'Asia/Riyadh', 'YYYY-MM-DD HH24:MI');
$$;

-- طلب معاينة جديد
CREATE OR REPLACE FUNCTION public.request_property_viewing(
  p_property_id uuid,
  p_proposed_at timestamptz,
  p_note text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_title text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;
  IF p_proposed_at IS NULL
     OR p_proposed_at < now() + interval '1 hour'
     OR p_proposed_at > now() + interval '60 days' THEN
    RAISE EXCEPTION 'invalid_viewing_time' USING ERRCODE = 'P0001';
  END IF;

  SELECT nullif(to_jsonb(p) ->> 'owner_id', '')::uuid,
         coalesce(nullif(trim(to_jsonb(p) ->> 'title'), ''), 'عقار')
  INTO v_owner, v_title
  FROM public.properties p
  WHERE p.id = p_property_id
    AND lower(coalesce(to_jsonb(p) ->> 'status', '')) <> 'deleted';

  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'property_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_owner = v_uid THEN
    RAISE EXCEPTION 'cannot_request_own_property' USING ERRCODE = 'P0001';
  END IF;

  -- حد يومي لمنع الإزعاج أو التلاعب.
  IF (SELECT count(*) FROM public.property_viewing_requests
      WHERE requester_id = v_uid
        AND created_at > now() - interval '24 hours') >= 10 THEN
    RAISE EXCEPTION 'viewing_rate_limited' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.property_viewing_requests (
    property_id, owner_id, requester_id, proposed_at, requester_note
  ) VALUES (
    p_property_id, v_owner, v_uid, p_proposed_at,
    nullif(left(trim(coalesce(p_note, '')), 300), '')
  )
  RETURNING id INTO v_id;

  PERFORM public._viewing_notify(
    v_owner, 'viewing_requested', 'طلب معاينة جديد',
    left(v_title, 80) || E'\nالموعد المقترح: ' || public._viewing_fmt(p_proposed_at)
      || E'\nيمكنك التأكيد أو الاعتذار أو اقتراح وقت بديل.',
    p_property_id, v_id
  );
  RETURN v_id;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'viewing_already_active' USING ERRCODE = 'P0001';
END;
$$;

-- رد المالك: confirm | decline | counter
CREATE OR REPLACE FUNCTION public.respond_property_viewing(
  p_request_id uuid,
  p_action text,
  p_counter_at timestamptz DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  r public.property_viewing_requests%ROWTYPE;
  v_note text := nullif(left(trim(coalesce(p_note, '')), 300), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;
  SELECT * INTO r FROM public.property_viewing_requests
  WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR r.owner_id <> v_uid THEN
    RAISE EXCEPTION 'request_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF r.status <> 'pending' THEN
    RAISE EXCEPTION 'request_not_pending' USING ERRCODE = 'P0001';
  END IF;

  IF p_action = 'confirm' THEN
    UPDATE public.property_viewing_requests
    SET status = 'confirmed', confirmed_at = r.proposed_at,
        owner_note = v_note, updated_at = now()
    WHERE id = r.id;
    PERFORM public._viewing_notify(
      r.requester_id, 'viewing_confirmed', 'تم تأكيد موعد المعاينة',
      'الموعد: ' || public._viewing_fmt(r.proposed_at),
      r.property_id, r.id);
  ELSIF p_action = 'decline' THEN
    UPDATE public.property_viewing_requests
    SET status = 'declined', owner_note = v_note, updated_at = now()
    WHERE id = r.id;
    PERFORM public._viewing_notify(
      r.requester_id, 'viewing_declined', 'تعذّر موعد المعاينة',
      'اعتذر المعلن عن الموعد المقترح. يمكنك طلب موعد آخر.',
      r.property_id, r.id);
  ELSIF p_action = 'counter' THEN
    IF p_counter_at IS NULL
       OR p_counter_at < now() + interval '1 hour'
       OR p_counter_at > now() + interval '60 days' THEN
      RAISE EXCEPTION 'invalid_viewing_time' USING ERRCODE = 'P0001';
    END IF;
    UPDATE public.property_viewing_requests
    SET status = 'counter_proposed', counter_at = p_counter_at,
        owner_note = v_note, updated_at = now()
    WHERE id = r.id;
    PERFORM public._viewing_notify(
      r.requester_id, 'viewing_counter_proposed', 'اقتراح موعد بديل للمعاينة',
      'الموعد البديل: ' || public._viewing_fmt(p_counter_at)
        || E'\nافتح الإعلان للقبول أو الاعتذار.',
      r.property_id, r.id);
  ELSE
    RAISE EXCEPTION 'invalid_action' USING ERRCODE = 'P0001';
  END IF;
END;
$$;

-- رد طالب المعاينة على الموعد البديل: accept | decline | cancel
CREATE OR REPLACE FUNCTION public.requester_respond_property_viewing(
  p_request_id uuid,
  p_action text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  r public.property_viewing_requests%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;
  SELECT * INTO r FROM public.property_viewing_requests
  WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR r.requester_id <> v_uid THEN
    RAISE EXCEPTION 'request_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF r.status NOT IN ('pending', 'counter_proposed', 'confirmed') THEN
    RAISE EXCEPTION 'request_closed' USING ERRCODE = 'P0001';
  END IF;

  IF p_action = 'accept' THEN
    IF r.status <> 'counter_proposed' OR r.counter_at IS NULL THEN
      RAISE EXCEPTION 'nothing_to_accept' USING ERRCODE = 'P0001';
    END IF;
    UPDATE public.property_viewing_requests
    SET status = 'confirmed', confirmed_at = r.counter_at, updated_at = now()
    WHERE id = r.id;
    PERFORM public._viewing_notify(
      r.owner_id, 'viewing_confirmed', 'تم قبول الموعد البديل',
      'الموعد المؤكد: ' || public._viewing_fmt(r.counter_at),
      r.property_id, r.id);
  ELSIF p_action IN ('decline', 'cancel') THEN
    UPDATE public.property_viewing_requests
    SET status = 'cancelled', updated_at = now()
    WHERE id = r.id;
    PERFORM public._viewing_notify(
      r.owner_id, 'viewing_cancelled', 'أُلغي طلب المعاينة',
      'ألغى المهتم طلب المعاينة.',
      r.property_id, r.id);
  ELSE
    RAISE EXCEPTION 'invalid_action' USING ERRCODE = 'P0001';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.request_property_viewing(uuid, timestamptz, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.respond_property_viewing(uuid, text, timestamptz, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.requester_respond_property_viewing(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_property_viewing(uuid, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_property_viewing(uuid, text, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.requester_respond_property_viewing(uuid, text) TO authenticated;

COMMIT;
