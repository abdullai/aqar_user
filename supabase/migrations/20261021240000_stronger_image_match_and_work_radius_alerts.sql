-- 1) بصمات صور أقوى (قص/قلب/إضاءة) + إشعار الموظفين تلقائيًا + تنظيف دوري
-- 2) «قريب من عملي» خادميًا: موقع عمل تقريبي (≈1 كم) يُحفظ مع البحث بموافقة صريحة
BEGIN;

-- ---------------------------------------------------------------------------
-- 1) بصمات الصور v2
-- ---------------------------------------------------------------------------
ALTER TABLE public.listing_image_hashes
  ADD COLUMN IF NOT EXISTS family text NOT NULL DEFAULT 'h',
  ADD COLUMN IF NOT EXISTS img_idx integer NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_listing_image_hashes_family
  ON public.listing_image_hashes (family, created_at DESC);

-- p_hashes: [{"i":1,"v":["h:<hex16>","d:<hex16>",...],"s":"<sha256>"}]
-- ويقبل الصيغة القديمة [{"p":"<hex16>","s":"..."}].
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
  v_images integer;
  v_rows integer;
  v_flags integer := 0;
  v_key uuid := coalesce(p_property_id, p_request_id);
  m record;
  s_uid uuid;
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

  CREATE TEMP TABLE IF NOT EXISTS _new_hashes2 (
    idx int, family text, phash bit(64), sha text
  ) ON COMMIT DROP;
  DELETE FROM _new_hashes2;

  -- الصيغة الجديدة
  INSERT INTO _new_hashes2 (idx, family, phash, sha)
  SELECT coalesce(nullif(e.value ->> 'i', '')::int, e.ord::int),
         split_part(v.val, ':', 1),
         ('x' || lower(split_part(v.val, ':', 2)))::bit(64),
         nullif(lower(coalesce(e.value ->> 's', '')), '')
  FROM jsonb_array_elements(p_hashes) WITH ORDINALITY AS e(value, ord)
  CROSS JOIN LATERAL jsonb_array_elements_text(
    CASE WHEN jsonb_typeof(e.value -> 'v') = 'array' THEN e.value -> 'v' ELSE '[]'::jsonb END
  ) AS v(val)
  WHERE v.val ~ '^[hd]:[0-9a-fA-F]{16}$';

  -- الصيغة القديمة
  INSERT INTO _new_hashes2 (idx, family, phash, sha)
  SELECT e.ord::int, 'h', ('x' || lower(e.value ->> 'p'))::bit(64),
         nullif(lower(coalesce(e.value ->> 's', '')), '')
  FROM jsonb_array_elements(p_hashes) WITH ORDINALITY AS e(value, ord)
  WHERE lower(coalesce(e.value ->> 'p', '')) ~ '^[0-9a-f]{16}$';

  -- تجاهل البصمات منخفضة الإنتروبيا (صور فارغة/موحّدة).
  DELETE FROM _new_hashes2 WHERE bit_count(phash) NOT BETWEEN 8 AND 56;

  SELECT count(DISTINCT idx), count(*) INTO v_images, v_rows FROM _new_hashes2;
  IF v_rows = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_hashes');
  END IF;

  FOR m IN
    SELECT h.owner_id AS m_owner,
           (array_agg(h.property_id) FILTER (WHERE h.property_id IS NOT NULL))[1] AS m_property,
           count(DISTINCT n.idx) AS matched,
           count(DISTINCT n.idx) FILTER (WHERE h.sha256 IS NOT NULL AND h.sha256 = n.sha) AS exact,
           min(bit_count(h.phash # n.phash))::int AS dist
    FROM (
      SELECT * FROM public.listing_image_hashes
      WHERE owner_id <> v_uid
      ORDER BY created_at DESC
      LIMIT 200000
    ) h
    JOIN _new_hashes2 n
      ON (h.family = n.family
          AND bit_count(h.phash # n.phash) <= CASE n.family WHEN 'd' THEN 6 ELSE 5 END)
      OR (h.sha256 IS NOT NULL AND h.sha256 = n.sha)
    GROUP BY h.owner_id
  LOOP
    -- صورة واحدة مشتركة لا تكفي لإعلان متعدد الصور (صور عامة/مخزّنة).
    CONTINUE WHEN m.matched < least(2, v_images) AND m.exact = 0;

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
    owner_id, property_id, request_id, phash, sha256, family, img_idx
  )
  SELECT v_uid, p_property_id, p_request_id, phash, sha, family, idx FROM _new_hashes2;

  IF v_flags > 0 THEN
    PERFORM public._viewing_notify(
      v_uid, 'listing_image_review', 'مراجعة صور الإعلان',
      'رصدنا تشابهًا بين بعض صور إعلانك وإعلان آخر. سيراجع فريقنا الحالة، ولا يتأثر نشر إعلانك الآن. إن كانت الصور لك فلا إجراء مطلوب منك.',
      p_property_id, NULL
    );
    -- تنبيه فريق الإشراف تلقائيًا (حتى 10 موظفين).
    BEGIN
      FOR s_uid IN
        SELECT s.user_id FROM public.platform_staff s
        WHERE coalesce(s.can_moderate, true) AND s.user_id <> v_uid
        LIMIT 10
      LOOP
        PERFORM public._viewing_notify(
          s_uid, 'listing_image_review', 'علامة صور جديدة للمراجعة',
          'رُصد تشابه صور بين إعلانين. افتح تبويب «سلامة الإعلانات» لاتخاذ القرار.',
          p_property_id, NULL
        );
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN jsonb_build_object('ok', true, 'registered', v_images, 'flagged', v_flags > 0);
END;
$$;

REVOKE ALL ON FUNCTION public.register_listing_image_hashes(jsonb, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_listing_image_hashes(jsonb, uuid, uuid) TO authenticated;

-- تنظيف دوري: بصمات إعلانات محذوفة أو أقدم من سنتين.
CREATE OR REPLACE FUNCTION public.cleanup_listing_image_hashes()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n integer;
BEGIN
  DELETE FROM public.listing_image_hashes h
  WHERE h.created_at < now() - interval '2 years'
     OR (h.property_id IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM public.properties p WHERE p.id = h.property_id));
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;
REVOKE ALL ON FUNCTION public.cleanup_listing_image_hashes() FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.unschedule('aqar_image_hash_cleanup');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    PERFORM cron.schedule(
      'aqar_image_hash_cleanup', '30 3 * * *',
      'SELECT public.cleanup_listing_image_hashes()'
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron schedule skipped: %', SQLERRM;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2) «قريب من عملي» في البحث المحفوظ (موقع تقريبي بموافقة المستخدم)
-- ---------------------------------------------------------------------------
ALTER TABLE public.saved_property_searches
  ADD COLUMN IF NOT EXISTS work_lat numeric(8, 5)
    CHECK (work_lat IS NULL OR work_lat BETWEEN -90 AND 90),
  ADD COLUMN IF NOT EXISTS work_lng numeric(8, 5)
    CHECK (work_lng IS NULL OR work_lng BETWEEN -180 AND 180),
  ADD COLUMN IF NOT EXISTS work_radius_km numeric(5, 1)
    CHECK (work_radius_km IS NULL OR work_radius_km BETWEEN 1 AND 100);

-- تقريب الإحداثيات إلى ≈1 كم لحماية الخصوصية، وإلزام الثلاثة معًا.
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
  IF NEW.work_lat IS NULL OR NEW.work_lng IS NULL THEN
    NEW.work_lat := NULL; NEW.work_lng := NULL; NEW.work_radius_km := NULL;
  ELSE
    NEW.work_lat := round(NEW.work_lat, 2);
    NEW.work_lng := round(NEW.work_lng, 2);
    NEW.work_radius_km := coalesce(NEW.work_radius_km, 10);
  END IF;
  RETURN NEW;
END;
$$;

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
  v_lat double precision := nullif(j ->> 'latitude', '')::double precision;
  v_lng double precision := nullif(j ->> 'longitude', '')::double precision;
  v_dist double precision;
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
    v_dist := NULL;

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

    -- قريب من العمل: يلزم إحداثيات العقار وأن تكون ضمن نصف القطر.
    IF v_ok AND s.work_lat IS NOT NULL THEN
      IF v_lat IS NULL OR v_lng IS NULL THEN
        v_ok := false;
      ELSE
        v_dist := 6371 * 2 * asin(sqrt(least(1,
          power(sin(radians(v_lat - s.work_lat::double precision) / 2), 2)
          + cos(radians(s.work_lat::double precision)) * cos(radians(v_lat))
            * power(sin(radians(v_lng - s.work_lng::double precision) / 2), 2)
        )));
        v_ok := v_dist <= coalesce(s.work_radius_km, 10)::double precision;
      END IF;
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
      CASE WHEN v_dist IS NOT NULL
        THEN 'يبعد نحو ' || round(v_dist::numeric, 1)::text || ' كم عن عملك' END,
      CASE WHEN array_length(s.keywords, 1) > 0
        THEN array_to_string(s.keywords, ' ') END
    );

    v_title_ar := 'عقار جديد يطابق بحثك';
    v_body_ar := left(v_title, 80)
      || CASE WHEN v_price IS NOT NULL
           THEN ' — ' || to_char(v_price, 'FM999,999,999,999') || ' ﷼' ELSE '' END
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

COMMIT;
