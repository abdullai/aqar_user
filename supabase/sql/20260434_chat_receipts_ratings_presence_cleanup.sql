-- Chat: إيصالات رسائل (تم التسليم / تم القراءة)، آخر ظهور، تقييمات الأقران،
-- حذف محادثات العقار عند البيع/الحذف، ودالة صيانة للمساحة (اختياري عبر cron).

-- ── 1) أعمدة الرسائل ─────────────────────────────────────────────────────
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS delivered_at timestamptz,
  ADD COLUMN IF NOT EXISTS read_at timestamptz;

COMMENT ON COLUMN public.messages.delivered_at IS 'وقت وصول الرسالة لجهاز المستلم (علامتي ✓✓ رمادي)';
COMMENT ON COLUMN public.messages.read_at IS 'وقت قراءة المستلم (علامتي ✓✓ زرقاء)';

-- ── 2) آخر ظهور في الدردشة ───────────────────────────────────────────────
ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS chat_last_seen_at timestamptz;

COMMENT ON COLUMN public.users_profiles.chat_last_seen_at IS 'آخر نشاط للمستخدم في الدردشة (للعرض كـ «آخر ظهور»)';

-- ── 3) تقييمات بين المستخدمين (مسوّق/مستخدم) ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_peer_ratings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rater_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  rated_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  stars smallint NOT NULL CHECK (stars >= 1 AND stars <= 5),
  comment text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_user_peer_ratings_pair UNIQUE (rater_user_id, rated_user_id),
  CONSTRAINT chk_user_peer_ratings_no_self CHECK (rater_user_id <> rated_user_id)
);

CREATE INDEX IF NOT EXISTS idx_user_peer_ratings_rated
  ON public.user_peer_ratings (rated_user_id);

ALTER TABLE public.user_peer_ratings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_peer_ratings_select_authenticated ON public.user_peer_ratings;
CREATE POLICY user_peer_ratings_select_authenticated
  ON public.user_peer_ratings FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS user_peer_ratings_insert_own ON public.user_peer_ratings;
CREATE POLICY user_peer_ratings_insert_own
  ON public.user_peer_ratings FOR INSERT TO authenticated
  WITH CHECK (rater_user_id = auth.uid());

DROP POLICY IF EXISTS user_peer_ratings_update_own ON public.user_peer_ratings;
CREATE POLICY user_peer_ratings_update_own
  ON public.user_peer_ratings FOR UPDATE TO authenticated
  USING (rater_user_id = auth.uid())
  WITH CHECK (rater_user_id = auth.uid());

-- ── 4) دوال الإيصالات (SECURITY DEFINER لتجاوز RLS على messages) ───────────
CREATE OR REPLACE FUNCTION public.mark_chat_messages_delivered(p_cid uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.messages
  SET delivered_at = COALESCE(delivered_at, now())
  WHERE conversation_id = p_cid
    AND receiver_id = auth.uid()
    AND delivered_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION public.mark_chat_messages_read_receipts(p_cid uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.messages
  SET read_at = COALESCE(read_at, now())
  WHERE conversation_id = p_cid
    AND receiver_id = auth.uid()
    AND read_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION public.ping_chat_presence()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.users_profiles
  SET chat_last_seen_at = now()
  WHERE user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_peer_rating_summary(p_user_id uuid)
RETURNS TABLE (avg_stars numeric, rating_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    COALESCE(ROUND(AVG(stars)::numeric, 2), 0)::numeric,
    COUNT(*)::bigint
  FROM public.user_peer_ratings
  WHERE rated_user_id = p_user_id;
$$;

GRANT EXECUTE ON FUNCTION public.mark_chat_messages_delivered(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_chat_messages_read_receipts(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ping_chat_presence() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_peer_rating_summary(uuid) TO authenticated;

-- ── 5) حذف محادثات العقار عند البيع/الأرشفة/حذف المستخدم للإعلان ───────────
CREATE OR REPLACE FUNCTION public.purge_property_chat_data(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_property_id IS NULL THEN
    RETURN;
  END IF;
  DELETE FROM public.messages m
  USING public.conversations c
  WHERE m.conversation_id = c.id
    AND c.property_id = p_property_id;

  DELETE FROM public.conversations
  WHERE property_id = p_property_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_property_chat_cleanup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.purge_property_chat_data(OLD.id);
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    v_status := lower(trim(COALESCE(NEW.status::text, '')));
    IF v_status IN (
         'sold', 'deleted', 'archived', 'archive', 'removed',
         'inactive', 'closed', 'hidden'
       )
    THEN
      PERFORM public.purge_property_chat_data(NEW.id);
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_property_chat_cleanup ON public.properties;
CREATE TRIGGER trg_property_chat_cleanup
  AFTER DELETE OR UPDATE OF status
  ON public.properties
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_property_chat_cleanup();

COMMENT ON FUNCTION public.purge_property_chat_data IS
  'حذف رسائل ومحادثات العقار (للمساحة والخصوصية بعد البيع/الأرشفة).';

-- ── 6) صيانة اختيارية: حذف محادثات عقارات قديمة جداً غير النشطة ───────────
CREATE OR REPLACE FUNCTION public.cleanup_stale_property_chats(p_days int DEFAULT 365)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int := 0;
BEGIN
  IF p_days < 30 THEN
    p_days := 30;
  END IF;

  DELETE FROM public.messages m
  USING public.conversations c, public.properties p
  WHERE m.conversation_id = c.id
    AND c.property_id = p.id
    AND p.updated_at < (now() - (p_days::text || ' days')::interval)
    AND lower(trim(COALESCE(p.status::text, ''))) IN (
      'draft', 'inactive', 'closed', 'archived', 'hidden'
    );

  GET DIAGNOSTICS n = ROW_COUNT;

  DELETE FROM public.conversations c
  USING public.properties p
  WHERE c.property_id = p.id
    AND p.updated_at < (now() - (p_days::text || ' days')::interval)
    AND lower(trim(COALESCE(p.status::text, ''))) IN (
      'draft', 'inactive', 'closed', 'archived', 'hidden'
    );

  RETURN n;
END;
$$;

COMMENT ON FUNCTION public.cleanup_stale_property_chats IS
  'للجدولة (pg_cron): حذف دردشات عقارات غير محدّثة منذ p_days وحالتها غير نشطة.';
