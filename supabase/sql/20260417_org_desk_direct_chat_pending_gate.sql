-- =============================================================================
-- مكتب المؤسسة: دردشة مباشرة بين أعضاء الفريق (kind=direct)، بوابة طلب انضمام
-- معلّق، وإخفاء «آخر ظهور» للمستخدم.
-- طبّق يدوياً على مشروع Supabase بعد المراجعة.
-- =============================================================================

-- ── 1) إخفاء آخر ظهور (يعرض للآخرين نصاً محايداً عند التطبيق) ───────────────
ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS chat_last_seen_hidden boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.users_profiles.chat_last_seen_hidden IS
  'عند true لا يعرض التطبيق للآخرين وقت آخر ظهور الدردشة (يبقى التحديث الفني للخادم).';

-- ── 2) توسيع نوع المحادثة ليشمل direct (محادثة 1:1 داخل نفس المؤسسة) ─────
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
    EXECUTE format('ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS %I', conname);
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
      ADD CONSTRAINT conversations_kind_check_v20260417
      CHECK (kind IN ('support', 'property', 'direct'));
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ── 3) محادثة مباشرة بين عضوين في نفس المؤسسة (نشطة) ─────────────────────
CREATE OR REPLACE FUNCTION public.ensure_direct_conversation(p_peer uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_peer uuid := p_peer;
  v_id uuid;
BEGIN
  IF v_uid IS NULL OR v_peer IS NULL OR v_uid = v_peer THEN
    RAISE EXCEPTION 'bad_args';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM org_memberships a
    JOIN org_memberships b ON a.org_id = b.org_id
    WHERE a.user_id = v_uid
      AND b.user_id = v_peer
      AND a.status = 'active'
      AND b.status = 'active'
  ) THEN
    RAISE EXCEPTION 'not_same_org';
  END IF;

  SELECT c.id INTO v_id
  FROM conversations c
  WHERE c.kind = 'direct'
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

  INSERT INTO conversations (kind, user_id, counterparty_id, title, property_id)
  VALUES ('direct', v_uid, v_peer, NULL, NULL)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_direct_conversation(uuid) TO authenticated;

COMMENT ON FUNCTION public.ensure_direct_conversation IS
  'يجد أو ينشئ محادثة 1:1 بين المستخدم الحالي و p_peer عند انتمائهما لنفس org_memberships النشطة.';

-- ── 4) لافتة طلب انضمام معلّق (لبوابة ما بعد تسجيل الدخول) ─────────────────
CREATE OR REPLACE FUNCTION public.my_pending_org_join_banner()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'request_id', j.id,
    'org_id', j.org_id,
    'org_account_type', o.account_type,
    'created_at', j.created_at
  )
  FROM org_join_requests j
  JOIN org_units o ON o.id = j.org_id
  WHERE j.applicant_user_id = auth.uid()
    AND j.status = 'pending'
  ORDER BY j.created_at ASC
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.my_pending_org_join_banner() TO authenticated;

-- ── 5) تحديث إخفاء آخر ظهور ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_chat_last_seen_hidden(p_hidden boolean)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.users_profiles
  SET chat_last_seen_hidden = coalesce(p_hidden, false)
  WHERE user_id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.set_chat_last_seen_hidden(boolean) TO authenticated;
