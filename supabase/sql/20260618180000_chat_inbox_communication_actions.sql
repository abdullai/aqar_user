-- دردشات / إشعارات: أرشفة، إخفاء، حظر، قراءة الكل، إدارة قناة الفريق
-- Chat inbox actions: archive, hide, block, mark-all-read, team channel admin

-- ── 1) حالة المحادثة لكل مستخدم ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.conversation_user_states (
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL REFERENCES public.conversations (id) ON DELETE CASCADE,
  is_hidden boolean NOT NULL DEFAULT false,
  is_archived boolean NOT NULL DEFAULT false,
  hidden_at timestamptz,
  archived_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, conversation_id)
);

CREATE INDEX IF NOT EXISTS idx_conversation_user_states_user
  ON public.conversation_user_states (user_id, is_archived, is_hidden);

ALTER TABLE public.conversation_user_states ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS conversation_user_states_own ON public.conversation_user_states;
CREATE POLICY conversation_user_states_own ON public.conversation_user_states
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.conversation_user_states TO authenticated;

-- ── 2) حظر مستخدم في الدردشة (1:1) ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_chat_blocks (
  blocker_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  blocked_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_user_chat_blocks_blocked
  ON public.user_chat_blocks (blocked_id);

ALTER TABLE public.user_chat_blocks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_chat_blocks_own ON public.user_chat_blocks;
CREATE POLICY user_chat_blocks_own ON public.user_chat_blocks
  FOR ALL TO authenticated
  USING (blocker_id = auth.uid())
  WITH CHECK (blocker_id = auth.uid());

GRANT SELECT, INSERT, DELETE ON public.user_chat_blocks TO authenticated;

-- ── 3) إيقاف مؤقت لعضو عن دردشة الفريق ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.org_chat_member_suspensions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.org_units (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  suspended_by uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  suspended_until timestamptz NOT NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (org_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_org_chat_suspensions_active
  ON public.org_chat_member_suspensions (org_id, user_id, suspended_until);

ALTER TABLE public.org_chat_member_suspensions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS org_chat_suspensions_owner_write ON public.org_chat_member_suspensions;
CREATE POLICY org_chat_suspensions_owner_write ON public.org_chat_member_suspensions
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.org_units ou
      WHERE ou.id = org_id AND ou.owner_user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.org_units ou
      WHERE ou.id = org_id AND ou.owner_user_id = auth.uid()
    )
  );

-- ── 4) مساعد: هل المستخدم مالك المنشأة؟ ───────────────────────────────────
CREATE OR REPLACE FUNCTION public._is_org_owner(p_org_id uuid, p_uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.org_units ou
    WHERE ou.id = p_org_id AND ou.owner_user_id = p_uid
  );
$$;

-- ── 5) أرشفة / إخفاء / حذف محادثة لي ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.archive_conversation_for_me(p_cid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_kind text;
BEGIN
  IF v_me IS NULL OR p_cid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT c.kind::text INTO v_kind FROM public.conversations c WHERE c.id = p_cid;
  IF v_kind IS NULL THEN
    RAISE EXCEPTION 'conversation_not_found';
  END IF;
  IF v_kind = 'org_team_channel' THEN
    RAISE EXCEPTION 'team_channel_no_archive';
  END IF;

  INSERT INTO public.conversation_user_states (user_id, conversation_id, is_archived, archived_at, updated_at)
  VALUES (v_me, p_cid, true, now(), now())
  ON CONFLICT (user_id, conversation_id) DO UPDATE
    SET is_archived = true,
        archived_at = now(),
        updated_at = now();

  PERFORM public.mark_conversation_read(p_cid);
END;
$$;

CREATE OR REPLACE FUNCTION public.hide_conversation_for_me(p_cid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_kind text;
BEGIN
  IF v_me IS NULL OR p_cid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT c.kind::text INTO v_kind FROM public.conversations c WHERE c.id = p_cid;
  IF v_kind IS NULL THEN
    RAISE EXCEPTION 'conversation_not_found';
  END IF;
  IF v_kind = 'org_team_channel' THEN
    RAISE EXCEPTION 'team_channel_no_hide';
  END IF;

  INSERT INTO public.conversation_user_states (user_id, conversation_id, is_hidden, hidden_at, updated_at)
  VALUES (v_me, p_cid, true, now(), now())
  ON CONFLICT (user_id, conversation_id) DO UPDATE
    SET is_hidden = true,
        hidden_at = now(),
        updated_at = now();

  PERFORM public.mark_conversation_read(p_cid);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_conversation_for_me(p_cid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_kind text;
BEGIN
  IF v_me IS NULL OR p_cid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT c.kind::text INTO v_kind FROM public.conversations c WHERE c.id = p_cid;
  IF v_kind IS NULL THEN
    RAISE EXCEPTION 'conversation_not_found';
  END IF;
  IF v_kind = 'org_team_channel' THEN
    RAISE EXCEPTION 'team_channel_no_delete';
  END IF;

  PERFORM public.hide_conversation_for_me(p_cid);

  -- إخفاء كل الرسائل لدي في هذه المحادثة
  INSERT INTO public.message_user_hides (user_id, message_id, conversation_id)
  SELECT v_me, m.id, m.conversation_id
  FROM public.messages m
  WHERE m.conversation_id = p_cid
    AND NOT EXISTS (
      SELECT 1 FROM public.message_user_hides h
      WHERE h.user_id = v_me AND h.message_id = m.id
    )
  ON CONFLICT (user_id, message_id) DO NOTHING;

  -- حذف الإشعارات المرتبطة
  DELETE FROM public.in_app_notifications n
  WHERE n.user_id = v_me
    AND (
      n.data->>'conversation_id' = p_cid::text
      OR n.data->>'cid' = p_cid::text
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.unarchive_conversation_for_me(p_cid uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.conversation_user_states
  SET is_archived = false,
      archived_at = NULL,
      updated_at = now()
  WHERE user_id = auth.uid()
    AND conversation_id = p_cid;
$$;

-- ── 6) قراءة محادثة + قراءة الكل ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mark_conversation_read(p_cid uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_n integer := 0;
BEGIN
  IF v_me IS NULL OR p_cid IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE public.messages m
  SET read_at = COALESCE(m.read_at, now())
  WHERE m.conversation_id = p_cid
    AND m.receiver_id = v_me
    AND m.read_at IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  UPDATE public.in_app_notifications n
  SET is_read = true
  WHERE n.user_id = v_me
    AND n.is_read = false
    AND (
      n.data->>'conversation_id' = p_cid::text
      OR n.data->>'cid' = p_cid::text
    );

  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_all_conversations_read()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_n integer := 0;
BEGIN
  IF v_me IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE public.messages m
  SET read_at = COALESCE(m.read_at, now())
  WHERE m.receiver_id = v_me
    AND m.read_at IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  UPDATE public.in_app_notifications n
  SET is_read = true
  WHERE n.user_id = v_me
    AND n.is_read = false
    AND (
      lower(n.type::text) IN ('chat_message', 'message', 'chat')
      OR n.data->>'deep_route' = 'chat'
      OR n.data->>'main_tab' = 'chat'
      OR n.data ? 'conversation_id'
    );

  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_all_in_app_notifications_read()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n integer := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE public.in_app_notifications n
  SET is_read = true
  WHERE n.user_id = auth.uid()
    AND n.is_read = false;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  RETURN v_n;
END;
$$;

-- ── 7) حظر / فك الحظر ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.block_chat_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL OR p_user_id IS NULL OR p_user_id = v_me THEN
    RAISE EXCEPTION 'invalid_block';
  END IF;

  INSERT INTO public.user_chat_blocks (blocker_id, blocked_id)
  VALUES (v_me, p_user_id)
  ON CONFLICT (blocker_id, blocked_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.unblock_chat_user(p_user_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM public.user_chat_blocks
  WHERE blocker_id = auth.uid()
    AND blocked_id = p_user_id;
$$;

CREATE OR REPLACE FUNCTION public.is_chat_user_blocked(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_chat_blocks b
    WHERE b.blocker_id = auth.uid()
      AND b.blocked_id = p_user_id
  );
$$;

-- ── 8) إدارة قناة الفريق (مدير فقط) ────────────────────────────────────────
ALTER TABLE public.org_team_channel_posts
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

CREATE OR REPLACE FUNCTION public.admin_delete_org_channel_post(p_post_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_org uuid;
BEGIN
  IF v_me IS NULL OR p_post_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT p.org_id INTO v_org
  FROM public.org_team_channel_posts p
  WHERE p.id = p_post_id;

  IF v_org IS NULL OR NOT public._is_org_owner(v_org, v_me) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.messages m
  SET deleted_for_everyone_at = now(),
      content = '…'
  WHERE m.org_channel_post_id = p_post_id
    AND m.deleted_for_everyone_at IS NULL;

  UPDATE public.org_team_channel_posts p
  SET body = '…',
      deleted_at = now()
  WHERE p.id = p_post_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_suspend_org_chat_member(
  p_org_id uuid,
  p_user_id uuid,
  p_hours integer DEFAULT 24,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_hours integer := GREATEST(1, LEAST(COALESCE(p_hours, 24), 720));
BEGIN
  IF v_me IS NULL OR p_org_id IS NULL OR p_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF NOT public._is_org_owner(p_org_id, v_me) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  INSERT INTO public.org_chat_member_suspensions (
    org_id, user_id, suspended_by, suspended_until, reason
  )
  VALUES (
    p_org_id,
    p_user_id,
    v_me,
    now() + make_interval(hours => v_hours),
    NULLIF(btrim(coalesce(p_reason, '')), '')
  )
  ON CONFLICT (org_id, user_id) DO UPDATE
    SET suspended_by = v_me,
        suspended_until = now() + make_interval(hours => v_hours),
        reason = EXCLUDED.reason,
        created_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_unsuspend_org_chat_member(
  p_org_id uuid,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public._is_org_owner(p_org_id, auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  DELETE FROM public.org_chat_member_suspensions
  WHERE org_id = p_org_id AND user_id = p_user_id;
END;
$$;

-- ── 9) get_chat_list2 — فلترة الأرشيف/الإخفاء + إيقاف الفريق ───────────────
DROP FUNCTION IF EXISTS public.get_chat_list2(integer);

CREATE FUNCTION public.get_chat_list2(
  p_limit integer DEFAULT 80,
  p_archived_only boolean DEFAULT false
)
RETURNS TABLE (
  conversation_id uuid,
  kind text,
  title text,
  other_user_id uuid,
  other_full_name text,
  other_phone text,
  other_avatar_url text,
  last_message text,
  last_message_at timestamptz,
  unread_count bigint,
  org_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH me AS (
    SELECT auth.uid() AS uid
  ),
  base_direct AS (
    SELECT
      c.id AS cid,
      c.kind AS k,
      c.title AS ttl,
      c.created_at AS c_created,
      CASE
        WHEN c.user_id = (SELECT uid FROM me) THEN c.counterparty_id
        ELSE c.user_id
      END AS oid,
      c.org_id AS org_pk
    FROM public.conversations c,
         me
    WHERE me.uid IS NOT NULL
      AND c.kind IS DISTINCT FROM 'org_team_channel'
      AND (c.user_id = me.uid OR c.counterparty_id = me.uid)
      AND NOT EXISTS (
        SELECT 1 FROM public.conversation_user_states cus
        WHERE cus.user_id = me.uid
          AND cus.conversation_id = c.id
          AND cus.is_hidden = true
      )
      AND (
        p_archived_only = COALESCE((
          SELECT cus2.is_archived
          FROM public.conversation_user_states cus2
          WHERE cus2.user_id = me.uid AND cus2.conversation_id = c.id
        ), false)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.user_chat_blocks blk
        WHERE blk.blocker_id = me.uid
          AND blk.blocked_id = CASE
            WHEN c.user_id = me.uid THEN c.counterparty_id
            ELSE c.user_id
          END
      )
  ),
  base_org_channel AS (
    SELECT
      c.id AS cid,
      c.kind AS k,
      c.title AS ttl,
      c.created_at AS c_created,
      ou.owner_user_id AS oid,
      c.org_id AS org_pk
    FROM public.conversations c
    JOIN public.org_memberships m ON m.org_id = c.org_id
    JOIN public.org_units ou ON ou.id = c.org_id,
         me
    WHERE me.uid IS NOT NULL
      AND c.kind = 'org_team_channel'
      AND c.org_id IS NOT NULL
      AND m.user_id = me.uid
      AND m.status = 'active'
      AND NOT EXISTS (
        SELECT 1 FROM public.org_chat_member_suspensions s
        WHERE s.org_id = c.org_id
          AND s.user_id = me.uid
          AND s.suspended_until > now()
      )
      AND p_archived_only = false
  ),
  base AS (
    SELECT * FROM base_direct
    UNION ALL
    SELECT * FROM base_org_channel
  ),
  last_msg AS (
    SELECT DISTINCT ON (m.conversation_id)
      m.conversation_id AS cid,
      CASE
        WHEN m.deleted_for_everyone_at IS NOT NULL THEN '…'
        ELSE m.content
      END AS body,
      m.created_at AS ts
    FROM public.messages m,
         me
    WHERE m.conversation_id IN (SELECT b.cid FROM base b)
      AND NOT EXISTS (
        SELECT 1 FROM public.message_user_hides h
        WHERE h.message_id = m.id AND h.user_id = me.uid
      )
    ORDER BY m.conversation_id, m.created_at DESC NULLS LAST
  ),
  unread AS (
    SELECT m.conversation_id AS cid, COUNT(*)::bigint AS n
    FROM public.messages m, me
    WHERE me.uid IS NOT NULL
      AND m.receiver_id = me.uid
      AND m.read_at IS NULL
      AND m.deleted_for_everyone_at IS NULL
      AND m.conversation_id IN (SELECT b.cid FROM base b)
      AND NOT EXISTS (
        SELECT 1 FROM public.message_user_hides h
        WHERE h.message_id = m.id AND h.user_id = me.uid
      )
    GROUP BY m.conversation_id
  )
  SELECT
    b.cid AS conversation_id,
    b.k::text AS kind,
    NULLIF(btrim(b.ttl::text), '') AS title,
    b.oid AS other_user_id,
    NULLIF(btrim(COALESCE(up.full_name_ar::text, up.full_name_en::text, up.full_name::text, up.username::text, '')), '') AS other_full_name,
    NULLIF(btrim(up.phone::text), '') AS other_phone,
    NULLIF(btrim(up.avatar_url::text), '') AS other_avatar_url,
    LEFT(btrim(COALESCE(lm.body::text, '')), 500) AS last_message,
    lm.ts AS last_message_at,
    COALESCE(u.n, 0::bigint) AS unread_count,
    b.org_pk AS org_id
  FROM base b
  LEFT JOIN last_msg lm ON lm.cid = b.cid
  LEFT JOIN unread u ON u.cid = b.cid
  LEFT JOIN public.users_profiles up ON up.user_id = b.oid
  ORDER BY COALESCE(lm.ts, b.c_created) DESC NULLS LAST, b.cid DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 80), 200));
$$;

GRANT EXECUTE ON FUNCTION public.get_chat_list2(integer, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_conversation_for_me(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hide_conversation_for_me(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_conversation_for_me(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unarchive_conversation_for_me(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_conversation_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_all_conversations_read() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_all_in_app_notifications_read() TO authenticated;
GRANT EXECUTE ON FUNCTION public.block_chat_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unblock_chat_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_chat_user_blocked(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_org_channel_post(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_suspend_org_chat_member(uuid, uuid, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_unsuspend_org_chat_member(uuid, uuid) TO authenticated;

-- Realtime (اختياري — فعّل من لوحة Supabase إن لزم)
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.conversation_user_states;
