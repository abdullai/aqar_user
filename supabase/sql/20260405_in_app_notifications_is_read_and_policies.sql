-- =============================================================================
-- in_app_notifications: حالة القراءة + سياسات خصوصية (كل مستخدم يرى صفوفه فقط)
-- ملاحظة: الإدراج من العميل لطرف آخر (مثلاً مسوّق → مالك) يتطلب سياسة INSERT مفتوحة
-- لـ authenticated — يُفضّل لاحقاً استبدالها بـ RPC SECURITY DEFINER مع تحقق من العلاقة.
-- =============================================================================

BEGIN;

ALTER TABLE public.in_app_notifications
  ADD COLUMN IF NOT EXISTS is_read boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_in_app_notifications_username_unread
  ON public.in_app_notifications (username, created_at DESC)
  WHERE is_read IS NOT TRUE;

-- قراءة: فقط إشعارات المستخدم الحالي (حسب users_profiles.username)
DROP POLICY IF EXISTS in_app_notifications_select_own_username ON public.in_app_notifications;
CREATE POLICY in_app_notifications_select_own_username ON public.in_app_notifications
  FOR SELECT TO authenticated
  USING (
    username IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.users_profiles up
      WHERE up.user_id = auth.uid()
        AND trim(both from up.username::text) = trim(both from in_app_notifications.username::text)
    )
  );

-- تحديث (مثلاً is_read): نفس شرط الملكية
DROP POLICY IF EXISTS in_app_notifications_update_own_username ON public.in_app_notifications;
CREATE POLICY in_app_notifications_update_own_username ON public.in_app_notifications
  FOR UPDATE TO authenticated
  USING (
    username IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.users_profiles up
      WHERE up.user_id = auth.uid()
        AND trim(both from up.username::text) = trim(both from in_app_notifications.username::text)
    )
  )
  WITH CHECK (
    username IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.users_profiles up
      WHERE up.user_id = auth.uid()
        AND trim(both from up.username::text) = trim(both from in_app_notifications.username::text)
    )
  );

-- إدراج من تطبيق موثوق (مسوّق يرسل لمعلن، إلخ). راجع الأمان على الإنتاج.
DROP POLICY IF EXISTS in_app_notifications_insert_authenticated ON public.in_app_notifications;
CREATE POLICY in_app_notifications_insert_authenticated ON public.in_app_notifications
  FOR INSERT TO authenticated
  WITH CHECK (true);

ALTER TABLE public.in_app_notifications ENABLE ROW LEVEL SECURITY;

-- دالة الإشعارات من سير العمل
CREATE OR REPLACE FUNCTION public.workflow_create_notification(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_entity_type text DEFAULT NULL,
  p_entity_id uuid DEFAULT NULL,
  p_data jsonb DEFAULT '{}'::jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_username text;
BEGIN
  SELECT nullif(trim(up.username), '')
  INTO v_username
  FROM public.users_profiles up
  WHERE up.user_id = p_user_id
  LIMIT 1;

  IF v_username IS NULL THEN
    RAISE EXCEPTION 'target_username_not_found';
  END IF;

  INSERT INTO public.in_app_notifications (
    username,
    type,
    title,
    body,
    data,
    created_at,
    is_read
  ) VALUES (
    v_username,
    p_type,
    p_title,
    p_body,
    coalesce(p_data, '{}'::jsonb) ||
      jsonb_build_object(
        'entity_type', p_entity_type,
        'entity_id', p_entity_id
      ),
    now(),
    false
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.workflow_create_notification(uuid, text, text, text, text, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.workflow_create_notification(uuid, text, text, text, text, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.workflow_create_notification(uuid, text, text, text, text, uuid, jsonb) TO service_role;

COMMIT;
