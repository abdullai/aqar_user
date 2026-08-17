-- =============================================================================
-- هيكل مقترح: طلب انضمام بـ «رقم عملي» (recruit_join_code على org_units) — يتطلب RLS وواجهات
-- وربط إشعارات. طبّق بعد مراجعة السياسات. (لا يُفعّل تلقائياً من التطبيق حتى تكتمل.)
-- =============================================================================
/*
BEGIN;

CREATE TABLE IF NOT EXISTS public.org_join_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.org_units (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  full_name_snapshot text,
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  decided_by_user_id uuid REFERENCES auth.users (id)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_org_join_pending_user
  ON public.org_join_requests (org_id, user_id)
  WHERE status = 'pending';

ALTER TABLE public.org_join_requests ENABLE ROW LEVEL SECURITY;

-- TODO: سياسات SELECT/INSERT/UPDATE حسب دور المالك والطالب

COMMIT;
*/
