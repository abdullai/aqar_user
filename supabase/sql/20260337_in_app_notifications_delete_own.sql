-- السماح للمستخدم بحذف إشعاراته داخل التطبيق (حسب username المطابق للملف).

DROP POLICY IF EXISTS in_app_notifications_delete_own_username ON public.in_app_notifications;

CREATE POLICY in_app_notifications_delete_own_username ON public.in_app_notifications
  FOR DELETE TO authenticated
  USING (
    username IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.users_profiles up
      WHERE up.user_id = auth.uid()
        AND trim(both from up.username::text) = trim(both from in_app_notifications.username::text)
    )
  );
