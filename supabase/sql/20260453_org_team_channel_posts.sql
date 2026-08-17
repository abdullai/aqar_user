-- =============================================================================
-- قناة فريق المؤسسة: منشورات جماعية (ليست جدول messages 1:1)
-- يظهر في «إدارتي» → دردشة الفريق → «قناة الفريق».
-- طبّق يدوياً على Supabase بعد org_memberships / org_units.
-- اختياري: Dashboard → Database → Replication → فعّل org_team_channel_posts للـ Realtime.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.org_team_channel_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  org_id uuid NOT NULL,
  author_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  body text NOT NULL,
  CONSTRAINT org_team_channel_posts_body_len CHECK (
    char_length(trim(body)) > 0 AND char_length(body) <= 4000
  )
);

CREATE INDEX IF NOT EXISTS idx_org_team_channel_posts_org_created
  ON public.org_team_channel_posts (org_id, created_at DESC);

ALTER TABLE public.org_team_channel_posts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS org_team_channel_posts_select_members
  ON public.org_team_channel_posts;
CREATE POLICY org_team_channel_posts_select_members
  ON public.org_team_channel_posts
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.org_memberships m
      WHERE m.org_id = org_team_channel_posts.org_id
        AND m.user_id = auth.uid()
        AND m.status = 'active'
    )
  );

DROP POLICY IF EXISTS org_team_channel_posts_insert_members
  ON public.org_team_channel_posts;
CREATE POLICY org_team_channel_posts_insert_members
  ON public.org_team_channel_posts
  FOR INSERT
  TO authenticated
  WITH CHECK (
    author_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.org_memberships m
      WHERE m.org_id = org_team_channel_posts.org_id
        AND m.user_id = auth.uid()
        AND m.status = 'active'
    )
  );

COMMENT ON TABLE public.org_team_channel_posts IS
  'منشورات قناة الفريق داخل المؤسسة؛ منفصلة عن محادثات messages المباشرة.';

GRANT SELECT, INSERT ON public.org_team_channel_posts TO authenticated;

-- محاولة إضافة الجدول لمنشور Realtime (قد تفشل حسب صلاحيات المشروع)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.org_team_channel_posts;
EXCEPTION
  WHEN undefined_object THEN NULL;
  WHEN insufficient_privilege THEN NULL;
  WHEN duplicate_object THEN NULL;
END $$;
