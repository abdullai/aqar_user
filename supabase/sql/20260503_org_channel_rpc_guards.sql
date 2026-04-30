-- =============================================================================
-- حراسة RPC للدردشة مع قناة المؤسسة (بعد 20260502)
-- 1) منع تعديل / حذف-للجميع لرسائل fan-out المرتبطة بمنشور القناة
-- 2) اعتبار عضو المؤسسة النشط مشاركاً في محادثة org_team_channel
-- طبّق بعد 20260502_org_team_channel_unified_inbox.sql و 20260501 (تعديل الرسالة الحالي).
-- =============================================================================

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
  v_has_attach boolean;
BEGIN
  IF v_me IS NULL OR p_message_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT m.conversation_id, m.created_at, m.deleted_for_everyone_at,
    (NULLIF(btrim(COALESCE(m.attachment_url::text, '')), '') IS NOT NULL)
  INTO v_conv, v_created, v_deleted, v_has_attach
  FROM public.messages m
  WHERE m.id = p_message_id;

  IF v_conv IS NULL THEN
    RAISE EXCEPTION 'message_not_found';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.messages mx
    WHERE mx.id = p_message_id AND mx.org_channel_post_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'org_channel_broadcast_not_editable';
  END IF;

  IF v_deleted IS NOT NULL THEN
    RAISE EXCEPTION 'message_revoked';
  END IF;

  v_new := btrim(COALESCE(p_new_content, ''));
  IF v_new = '' AND NOT coalesce(v_has_attach, false) THEN
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
  'تعديل نص الرسالة؛ لا ينطبق على نسخ منشور قناة الفريق (fan-out).';

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

  IF EXISTS (
    SELECT 1 FROM public.messages mx
    WHERE mx.id = p_message_id AND mx.org_channel_post_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'org_channel_broadcast_not_revocable';
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
  'حذف للجميع؛ لا ينطبق على نسخ منشور قناة الفريق.';
