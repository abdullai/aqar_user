-- =============================================================================
-- قناة المؤسسة + صندوق محادثات واحد: دمج منشورات القناة مع messages + get_chat_list2
--
-- طبّق بعد:
--   20260453_org_team_channel_posts.sql
--   20260430_messages_edit_revoke_whatsapp.sql (أو ما يعادله)
--   20260501_message_hide_for_me.sql
--
-- ماذا يفعل:
--   - org_id على conversations + kind = org_team_channel
--   - عمود messages.org_channel_post_id + نسخ لكل عضو (fan-out) عند INSERT منشور
--   - إشعارات داخلية + push عبر trigger on in_app_notifications الحالي
--   - get_chat_list2 يضم قناة الفريق مع المحادثات 1:1
--   - hide_chat_message_for_me يخفي كل النسخ لنفس المنشور لدى المستلم
--
-- بعدها (اختياري لكن موصى): 20260503_org_channel_rpc_guards.sql
-- =============================================================================

-- ── 1) conversations.org_id + نوع org_team_channel ─────────────────────────
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS org_id uuid REFERENCES public.org_units (id) ON DELETE CASCADE;

COMMENT ON COLUMN public.conversations.org_id IS
  'عند kind=org_team_channel يحدد المؤسسة؛ محادثة قناة واحدة لكل org.';

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
      ADD CONSTRAINT conversations_kind_check_v20260502
      CHECK (kind IN (
        'support',
        'property',
        'direct',
        'market_request',
        'org_team_channel'
      ));
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_conversations_one_org_team_channel
  ON public.conversations (org_id)
  WHERE kind = 'org_team_channel' AND org_id IS NOT NULL;

-- ── 2) messages.org_channel_post_id ─────────────────────────────────────────
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS org_channel_post_id uuid
    REFERENCES public.org_team_channel_posts (id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_messages_org_channel_post
  ON public.messages (org_channel_post_id)
  WHERE org_channel_post_id IS NOT NULL;

COMMENT ON COLUMN public.messages.org_channel_post_id IS
  'عند قناة المؤسسة: ربط نسخة الرسالة بمنشور القناة (fan-out لكل عضو).';

-- ── 3) إنشاء / جلب محادثة القناة ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ensure_org_team_channel_conversation(p_org_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_cid uuid;
BEGIN
  IF v_uid IS NULL OR p_org_id IS NULL THEN
    RAISE EXCEPTION 'bad_args';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.org_memberships m
    WHERE m.org_id = p_org_id
      AND m.user_id = v_uid
      AND m.status = 'active'
  ) THEN
    RAISE EXCEPTION 'not_org_member';
  END IF;

  SELECT c.id INTO v_cid
  FROM public.conversations c
  WHERE c.kind = 'org_team_channel'
    AND c.org_id = p_org_id
  LIMIT 1;

  IF v_cid IS NOT NULL THEN
    RETURN v_cid;
  END IF;

  SELECT owner_user_id INTO v_owner
  FROM public.org_units
  WHERE id = p_org_id;

  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'org_not_found';
  END IF;

  INSERT INTO public.conversations (
    kind,
    user_id,
    counterparty_id,
    title,
    org_id
  )
  VALUES (
    'org_team_channel',
    v_owner,
    v_owner,
    'قناة الفريق',
    p_org_id
  )
  RETURNING id INTO v_cid;

  RETURN v_cid;
EXCEPTION
  WHEN unique_violation THEN
    SELECT c.id INTO v_cid
    FROM public.conversations c
    WHERE c.kind = 'org_team_channel'
      AND c.org_id = p_org_id
    LIMIT 1;
    IF v_cid IS NULL THEN
      RAISE;
    END IF;
    RETURN v_cid;
END;
$$;

COMMENT ON FUNCTION public.ensure_org_team_channel_conversation(uuid) IS
  'عضو نشط: أنشئ أو أعد id محادثة قناة الفريق للمؤسسة.';

GRANT EXECUTE ON FUNCTION public.ensure_org_team_channel_conversation(uuid) TO authenticated;

-- ── 4) إشعار الأعضاء (يمر عبر push outbox عند تفعيله) ──────────────────────
CREATE OR REPLACE FUNCTION public.notify_org_team_channel_members(
  p_post_id uuid,
  p_org_id uuid,
  p_author_id uuid,
  p_conversation_id uuid,
  p_body text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m record;
  v_preview text := left(trim(coalesce(p_body, '')), 200);
BEGIN
  FOR m IN
    SELECT
      mm.user_id,
      COALESCE(
        NULLIF(btrim(up.username::text), ''),
        mm.user_id::text
      ) AS uname
    FROM public.org_memberships mm
    LEFT JOIN public.users_profiles up ON up.user_id = mm.user_id
    WHERE mm.org_id = p_org_id
      AND mm.status = 'active'
      AND mm.user_id IS DISTINCT FROM p_author_id
  LOOP
    INSERT INTO public.in_app_notifications (
      username,
      user_id,
      type,
      title,
      body,
      data,
      created_at,
      is_read
    )
    VALUES (
      m.uname,
      m.user_id,
      'chat_message',
      CASE
        WHEN btrim(coalesce(p_body, '')) <> '' THEN left(btrim(p_body), 200)
        ELSE 'Team channel'
      END,
      CASE
        WHEN btrim(coalesce(p_body, '')) <> '' THEN left(btrim(p_body), 500)
        ELSE ''
      END,
      jsonb_build_object(
        'main_tab', 'chat',
        'deep_route', 'chat',
        'conversation_id', p_conversation_id::text,
        'kind', 'chat_message',
        'type', 'chat_message',
        'org_channel_post_id', p_post_id::text,
        'title_ar', 'منشور قناة الفريق',
        'title_en', 'Team channel',
        'body_ar', v_preview,
        'body_en', v_preview,
        'role', 'peer'
      ),
      now(),
      false
    );
  END LOOP;
END;
$$;

-- ── 5) fan-out: منشور القناة → messages لكل عضو ───────────────────────────
CREATE OR REPLACE FUNCTION public.trg_org_team_channel_post_fanout()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cid uuid;
  m record;
BEGIN
  v_cid := public.ensure_org_team_channel_conversation(NEW.org_id);

  FOR m IN
    SELECT user_id
    FROM public.org_memberships
    WHERE org_id = NEW.org_id
      AND status = 'active'
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM public.messages x
      WHERE x.org_channel_post_id = NEW.id
        AND x.receiver_id = m.user_id
    ) THEN
      INSERT INTO public.messages (
        sender_id,
        receiver_id,
        conversation_id,
        content,
        org_channel_post_id,
        created_at
      )
      VALUES (
        NEW.author_id,
        m.user_id,
        v_cid,
        NEW.body,
        NEW.id,
        NEW.created_at
      );
    END IF;
  END LOOP;

  PERFORM public.notify_org_team_channel_members(
    NEW.id,
    NEW.org_id,
    NEW.author_id,
    v_cid,
    NEW.body
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_org_team_channel_post_fanout ON public.org_team_channel_posts;

CREATE TRIGGER trg_org_team_channel_post_fanout
  AFTER INSERT ON public.org_team_channel_posts
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_org_team_channel_post_fanout();

-- ── 6) hide_chat_message_for_me: كل النسخ لنفس منشور القناة ────────────────
CREATE OR REPLACE FUNCTION public.hide_chat_message_for_me(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_conv uuid;
  v_post uuid;
BEGIN
  IF v_me IS NULL OR p_message_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT m.conversation_id, m.org_channel_post_id
  INTO v_conv, v_post
  FROM public.messages m
  WHERE m.id = p_message_id;

  IF v_conv IS NULL THEN
    RAISE EXCEPTION 'message_not_found';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.conversations c
    WHERE c.id = v_conv AND (c.user_id = v_me OR c.counterparty_id = v_me)
  ) AND NOT EXISTS (
    SELECT 1
    FROM public.conversations c2
    JOIN public.org_memberships mm ON mm.org_id = c2.org_id
    WHERE c2.id = v_conv
      AND c2.kind = 'org_team_channel'
      AND mm.user_id = v_me
      AND mm.status = 'active'
  ) THEN
    RAISE EXCEPTION 'not_participant';
  END IF;

  IF v_post IS NOT NULL THEN
    INSERT INTO public.message_user_hides (user_id, message_id, conversation_id)
    SELECT v_me, mm.id, mm.conversation_id
    FROM public.messages mm
    WHERE mm.org_channel_post_id = v_post
      AND mm.receiver_id = v_me
    ON CONFLICT (user_id, message_id) DO NOTHING;
    RETURN;
  END IF;

  INSERT INTO public.message_user_hides (user_id, message_id, conversation_id)
  VALUES (v_me, p_message_id, v_conv)
  ON CONFLICT (user_id, message_id) DO NOTHING;
END;
$$;

-- ── 7) get_chat_list2 — دمج قناة الفريق ────────────────────────────────────
DROP FUNCTION IF EXISTS public.get_chat_list2(integer);

CREATE FUNCTION public.get_chat_list2(p_limit integer DEFAULT 80)
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
        WHEN m.deleted_for_everyone_at IS NOT NULL THEN
          '…'
        ELSE
          m.content
      END AS body,
      m.created_at AS ts
    FROM public.messages m,
         me
    WHERE m.conversation_id IN (SELECT b.cid FROM base b)
      AND NOT EXISTS (
        SELECT 1
        FROM public.message_user_hides h
        WHERE h.message_id = m.id
          AND h.user_id = me.uid
      )
    ORDER BY m.conversation_id, m.created_at DESC NULLS LAST
  ),
  unread AS (
    SELECT
      m.conversation_id AS cid,
      COUNT(*)::bigint AS n
    FROM public.messages m,
         me
    WHERE me.uid IS NOT NULL
      AND m.receiver_id = me.uid
      AND m.read_at IS NULL
      AND m.deleted_for_everyone_at IS NULL
      AND m.conversation_id IN (SELECT b.cid FROM base b)
      AND NOT EXISTS (
        SELECT 1
        FROM public.message_user_hides h
        WHERE h.message_id = m.id
          AND h.user_id = me.uid
      )
    GROUP BY m.conversation_id
  )
  SELECT
    b.cid AS conversation_id,
    b.k::text AS kind,
    NULLIF(btrim(b.ttl::text), '') AS title,
    b.oid AS other_user_id,
    NULLIF(
      btrim(
        COALESCE(
          up.full_name_ar::text,
          up.full_name_en::text,
          up.full_name::text,
          up.username::text,
          ''
        )
      ),
      ''
    ) AS other_full_name,
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

COMMENT ON FUNCTION public.get_chat_list2(integer) IS
  'قائمة محادثات + قناة الفريق؛ غير مقروء عبر messages؛ org_id لمزامنة العميل.';

GRANT EXECUTE ON FUNCTION public.get_chat_list2(integer) TO authenticated;

-- ── 8) محادثات قناة لكل مؤسسة قائمة (مرة واحدة بعد الترقية) ────────────────
INSERT INTO public.conversations (kind, user_id, counterparty_id, title, org_id)
SELECT
  'org_team_channel',
  ou.owner_user_id,
  ou.owner_user_id,
  'قناة الفريق',
  ou.id
FROM public.org_units ou
WHERE NOT EXISTS (
  SELECT 1
  FROM public.conversations c
  WHERE c.org_id = ou.id
    AND c.kind = 'org_team_channel'
);

-- ── 9) استيراد المنشورات القديمة إلى messages (مرة واحدة) ───────────────
INSERT INTO public.messages (
  sender_id,
  receiver_id,
  conversation_id,
  content,
  org_channel_post_id,
  created_at
)
SELECT
  p.author_id,
  m.user_id,
  c.id,
  p.body,
  p.id,
  p.created_at
FROM public.org_team_channel_posts p
JOIN public.conversations c
  ON c.org_id = p.org_id AND c.kind = 'org_team_channel'
JOIN public.org_memberships m
  ON m.org_id = p.org_id AND m.status = 'active'
WHERE NOT EXISTS (
  SELECT 1
  FROM public.messages x
  WHERE x.org_channel_post_id = p.id
    AND x.receiver_id = m.user_id
);

-- ملاحظة: لا تُعاد إشعارات للمنشورات المستوردة (كانت قديمة).
