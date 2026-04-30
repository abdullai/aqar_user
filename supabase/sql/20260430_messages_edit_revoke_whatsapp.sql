-- =============================================================================
-- رسائل الدردشة: تعديل النص (واتساب) وحذف للجميع — مع RPC آمنة SECURITY DEFINER
-- يعتمد على public.messages (sender_id, receiver_id, conversation_id, content, …).
-- طبّق بعد 20260434_chat_receipts_ratings_presence_cleanup.sql وملف get_chat_list2.
-- =============================================================================

-- ── أعمدة جديدة ────────────────────────────────────────────────────────────
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS edited_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_for_everyone_at timestamptz;

COMMENT ON COLUMN public.messages.edited_at IS 'وقت آخر تعديل لنص الرسالة من المرسل';
COMMENT ON COLUMN public.messages.deleted_for_everyone_at IS 'حذف للجميع؛ إخفاء المحتوى في الواجهات';

-- ── تعديل نص الرسالة: المرسل فقط، ولا يوجد رد بعدها في المحادثة ───────────
CREATE OR REPLACE FUNCTION public.edit_chat_message(p_message_id uuid, p_new_content text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_conv uuid;
  v_created timestamptz;
  v_deleted timestamptz;
  v_new text;
BEGIN
  IF v_me IS NULL OR p_message_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT m.conversation_id, m.created_at, m.deleted_for_everyone_at
    INTO v_conv, v_created, v_deleted
  FROM public.messages m
  WHERE m.id = p_message_id;

  IF v_conv IS NULL THEN
    RAISE EXCEPTION 'message_not_found';
  END IF;

  IF v_deleted IS NOT NULL THEN
    RAISE EXCEPTION 'message_revoked';
  END IF;

  v_new := btrim(COALESCE(p_new_content, ''));
  IF v_new = '' THEN
    RAISE EXCEPTION 'empty_content';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.messages m0
    WHERE m0.id = p_message_id AND m0.sender_id = v_me
  ) THEN
    RAISE EXCEPTION 'not_sender';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.conversations c
    WHERE c.id = v_conv AND (c.user_id = v_me OR c.counterparty_id = v_me)
  ) THEN
    RAISE EXCEPTION 'not_participant';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.messages m2
    WHERE m2.conversation_id = v_conv
      AND m2.created_at > v_created
  ) THEN
    RAISE EXCEPTION 'reply_exists';
  END IF;

  UPDATE public.messages
  SET
    content = v_new,
    edited_at = now()
  WHERE id = p_message_id
    AND sender_id = v_me
    AND deleted_for_everyone_at IS NULL;
END;
$$;

COMMENT ON FUNCTION public.edit_chat_message(uuid, text) IS
  'يعدّل نص رسالة المرسل إذا لم تُرد بعدها رسالة لاحقة في نفس المحادثة.';

-- ── حذف للجميع: المرسل فقط، خلال 48 ساعة من الإرسال ───────────────────────
CREATE OR REPLACE FUNCTION public.revoke_chat_message_for_everyone(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_conv uuid;
  v_created timestamptz;
BEGIN
  IF v_me IS NULL OR p_message_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT m.conversation_id, m.created_at
    INTO v_conv, v_created
  FROM public.messages m
  WHERE m.id = p_message_id;

  IF v_conv IS NULL THEN
    RAISE EXCEPTION 'message_not_found';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.messages m0
    WHERE m0.id = p_message_id AND m0.sender_id = v_me
  ) THEN
    RAISE EXCEPTION 'not_sender';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.conversations c
    WHERE c.id = v_conv AND (c.user_id = v_me OR c.counterparty_id = v_me)
  ) THEN
    RAISE EXCEPTION 'not_participant';
  END IF;

  IF v_created < (now() - interval '48 hours') THEN
    RAISE EXCEPTION 'revoke_window_expired';
  END IF;

  UPDATE public.messages
  SET
    deleted_for_everyone_at = now(),
    content = '',
    attachment_url = NULL,
    attachment_type = NULL
  WHERE id = p_message_id
    AND sender_id = v_me
    AND deleted_for_everyone_at IS NULL;
END;
$$;

COMMENT ON FUNCTION public.revoke_chat_message_for_everyone(uuid) IS
  'حذف رسالة لجميع المشاركين (48 ساعة) — المرسل فقط.';

GRANT EXECUTE ON FUNCTION public.edit_chat_message(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_chat_message_for_everyone(uuid) TO authenticated;

-- ── تحديث معاينة آخر رسالة في قائمة المحادثات ─────────────────────────────
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
  unread_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH me AS (
    SELECT auth.uid() AS uid
  ),
  base AS (
    SELECT
      c.id AS cid,
      c.kind AS k,
      c.title AS ttl,
      c.created_at AS c_created,
      CASE
        WHEN c.user_id = (SELECT uid FROM me) THEN c.counterparty_id
        ELSE c.user_id
      END AS oid
    FROM public.conversations c,
         me
    WHERE me.uid IS NOT NULL
      AND (c.user_id = me.uid OR c.counterparty_id = me.uid)
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
    FROM public.messages m
    WHERE m.conversation_id IN (SELECT b.cid FROM base b)
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
    COALESCE(u.n, 0::bigint) AS unread_count
  FROM base b
  LEFT JOIN last_msg lm ON lm.cid = b.cid
  LEFT JOIN unread u ON u.cid = b.cid
  LEFT JOIN public.users_profiles up ON up.user_id = b.oid
  ORDER BY COALESCE(lm.ts, b.c_created) DESC NULLS LAST, b.cid DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 80), 200));
$$;

COMMENT ON FUNCTION public.get_chat_list2(integer) IS
  'قائمة محادثات المستخدم: آخر رسالة (مع حذف للجميع كـ …)، غير مقروء، الطرف الآخر.';

GRANT EXECUTE ON FUNCTION public.get_chat_list2(integer) TO authenticated;
