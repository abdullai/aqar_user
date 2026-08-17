-- =============================================================================
-- قائمة المحادثات للتطبيق (RPC get_chat_list2)
-- يشمل: support, property, direct, market_request وأي kind آخر صفّه المستخدم فيه.
-- يعتمد على عمود messages.read_at لعدّ غير المقروء (انظر 20260434_chat_receipts…).
-- طبّق على Supabase بعد جداول conversations/messages/users_profiles الجاهزة.
--
-- إن وُجدت get_chat_list2 سابقاً بأعمدة/أنواع مختلفة، لا يكفي CREATE OR REPLACE —
-- يجب DROP أولاً (انظر أدناه).
-- =============================================================================

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
      m.content AS body,
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
  'قائمة محادثات المستخدم الحالي (واتساب): آخر رسالة، غير مقروء، الطرف الآخر؛ يشمل market_request.';

GRANT EXECUTE ON FUNCTION public.get_chat_list2(integer) TO authenticated;
