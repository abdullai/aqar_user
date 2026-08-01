-- =============================================================================
-- Harden in_app_notifications INSERT: no open WITH CHECK (true).
-- Cross-user notifies go through SECURITY DEFINER RPC only.
-- Self-insert (user_id = auth.uid()) remains allowed for rare client paths.
-- APPLY in Supabase SQL Editor if not yet migrated.
-- =============================================================================

DROP POLICY IF EXISTS in_app_notifications_insert_authenticated
  ON public.in_app_notifications;
DROP POLICY IF EXISTS in_app_notifications_insert_self
  ON public.in_app_notifications;

CREATE POLICY in_app_notifications_insert_self
  ON public.in_app_notifications
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id IS NOT NULL AND user_id = auth.uid());

-- Ensure workflow helper can still insert for any recipient (SECURITY DEFINER).
GRANT EXECUTE ON FUNCTION public.workflow_create_notification(
  uuid, text, text, text, text, uuid, jsonb
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.workflow_create_notification(
  uuid, text, text, text, text, uuid, jsonb
) TO service_role;

COMMENT ON POLICY in_app_notifications_insert_self ON public.in_app_notifications IS
  'Clients may only insert notifications for themselves; cross-user via workflow_create_notification.';
