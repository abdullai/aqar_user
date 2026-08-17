-- طلبات السوق: خصوصية اسم الطالب، عروض متعددة، محادثات kind=market_request
-- طبّق بعد 20260409_market_property_requests.sql
-- -----------------------------------------------------------------------------
-- 1) أعمدة إضافية على الطلبات
ALTER TABLE public.market_property_requests
  ADD COLUMN IF NOT EXISTS show_requester_name boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS requester_public_name text;

COMMENT ON COLUMN public.market_property_requests.show_requester_name IS
  'عند true يُعرض requester_public_name في البطاقة العامة.';
COMMENT ON COLUMN public.market_property_requests.requester_public_name IS
  'اسم للعرض العام (يملأه التطبيق من الملف الشخصي عند الموافقة).';

CREATE OR REPLACE FUNCTION public.touch_market_property_requests_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_market_property_requests_updated
  ON public.market_property_requests;
CREATE TRIGGER trg_market_property_requests_updated
  BEFORE UPDATE ON public.market_property_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_market_property_requests_updated_at();

-- -----------------------------------------------------------------------------
-- 2) عروض على الطلب (أكثر من مستخدم)
CREATE TABLE IF NOT EXISTS public.market_request_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  market_request_id uuid NOT NULL
    REFERENCES public.market_property_requests (id) ON DELETE CASCADE,
  offerer_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'submitted'
    CHECK (status IN ('submitted', 'accepted', 'rejected', 'withdrawn')),
  message text,
  price_offer numeric,
  CONSTRAINT market_request_offers_one_per_user UNIQUE (market_request_id, offerer_id)
);

CREATE INDEX IF NOT EXISTS idx_market_request_offers_request_created
  ON public.market_request_offers (market_request_id, created_at DESC);

ALTER TABLE public.market_request_offers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS market_request_offers_select_parties
  ON public.market_request_offers;
CREATE POLICY market_request_offers_select_parties
  ON public.market_request_offers
  FOR SELECT
  TO authenticated
  USING (
    offerer_id = auth.uid()
    OR EXISTS (
      SELECT 1
      FROM public.market_property_requests r
      WHERE r.id = market_request_id
        AND r.requester_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS market_request_offers_insert_eligible
  ON public.market_request_offers;
CREATE POLICY market_request_offers_insert_eligible
  ON public.market_request_offers
  FOR INSERT
  TO authenticated
  WITH CHECK (
    offerer_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.market_property_requests r
      WHERE r.id = market_request_id
        AND r.status = 'published'
        AND r.requester_id IS DISTINCT FROM auth.uid()
    )
  );

DROP POLICY IF EXISTS market_request_offers_update_offerer
  ON public.market_request_offers;
CREATE POLICY market_request_offers_update_offerer
  ON public.market_request_offers
  FOR UPDATE
  TO authenticated
  USING (offerer_id = auth.uid())
  WITH CHECK (offerer_id = auth.uid());

-- -----------------------------------------------------------------------------
-- 3) conversations.kind + market_request_id
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS market_request_id uuid
    REFERENCES public.market_property_requests (id) ON DELETE CASCADE;

DO $$
DECLARE
  conname text;
BEGIN
  FOR conname IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'conversations'
      AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) ILIKE '%kind%'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS %I',
      conname
    );
  END LOOP;
EXCEPTION
  WHEN undefined_table THEN NULL;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'conversations'
  ) THEN
    ALTER TABLE public.conversations
      ADD CONSTRAINT conversations_kind_check_v20260411
      CHECK (kind IN (
        'support',
        'property',
        'direct',
        'market_request'
      ));
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON COLUMN public.conversations.market_request_id IS
  'مرجع طلب السوق عند kind=market_request؛ property_id يبقى فارغاً.';

-- -----------------------------------------------------------------------------
-- 4) إنشاء/جلب محادثة طلب (SECURITY DEFINER)
CREATE OR REPLACE FUNCTION public.ensure_market_request_conversation(
  p_request_id uuid,
  p_counterparty uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_req record;
  v_peer uuid;
  v_title text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL OR p_request_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  SELECT id, requester_id, status, title
  INTO v_req
  FROM public.market_property_requests
  WHERE id = p_request_id;

  IF v_req.id IS NULL THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF v_req.status IS DISTINCT FROM 'published' AND v_req.requester_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'request_not_visible';
  END IF;

  IF v_uid = v_req.requester_id THEN
    IF p_counterparty IS NULL OR p_counterparty = v_uid THEN
      RAISE EXCEPTION 'counterparty_required';
    END IF;
    v_peer := p_counterparty;
  ELSE
    v_peer := v_req.requester_id;
  END IF;

  IF v_peer IS NULL OR v_peer = v_uid THEN
    RAISE EXCEPTION 'bad_peer';
  END IF;

  v_title := left(trim(coalesce(v_req.title, '')), 200);
  IF v_title = '' THEN
    v_title := 'Market request';
  END IF;

  SELECT c.id INTO v_id
  FROM public.conversations c
  WHERE c.kind = 'market_request'
    AND c.market_request_id = p_request_id
    AND c.property_id IS NULL
    AND (
      (c.user_id = v_uid AND c.counterparty_id = v_peer)
      OR (c.user_id = v_peer AND c.counterparty_id = v_uid)
    )
  ORDER BY c.created_at DESC NULLS LAST
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  INSERT INTO public.conversations (
    kind,
    user_id,
    counterparty_id,
    title,
    property_id,
    market_request_id
  )
  VALUES (
    'market_request',
    v_uid,
    v_peer,
    v_title,
    NULL,
    p_request_id
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_market_request_conversation(uuid, uuid)
  TO authenticated;

COMMENT ON FUNCTION public.ensure_market_request_conversation IS
  'يجد أو ينشئ محادثة 1:1 مرتبطة بطلب سوق منشور؛ الطالب يمرّر الطرف الآخر.';

-- -----------------------------------------------------------------------------
-- 5) قبول/رفض عرض (لصاحب الطلب فقط)
CREATE OR REPLACE FUNCTION public.respond_market_request_offer(
  p_offer_id uuid,
  p_action text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_req uuid;
  v_status text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  IF p_action NOT IN ('accept', 'reject') THEN
    RAISE EXCEPTION 'bad_action';
  END IF;

  SELECT o.market_request_id, o.status
  INTO v_req, v_status
  FROM public.market_request_offers o
  WHERE o.id = p_offer_id;

  IF v_req IS NULL THEN
    RAISE EXCEPTION 'offer_not_found';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.market_property_requests r
    WHERE r.id = v_req AND r.requester_id = v_uid
  ) THEN
    RAISE EXCEPTION 'not_request_owner';
  END IF;

  IF v_status IS DISTINCT FROM 'submitted' THEN
    RAISE EXCEPTION 'offer_not_pending';
  END IF;

  UPDATE public.market_request_offers
  SET
    status = CASE WHEN p_action = 'accept' THEN 'accepted' ELSE 'rejected' END,
    updated_at = now()
  WHERE id = p_offer_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.respond_market_request_offer(uuid, text)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- قائمة المحادثات: نفّذ supabase/sql/20260412_get_chat_list2_market_request.sql
-- (استبدال get_chat_list2 ليشمل market_request وجميع الأنواع).
