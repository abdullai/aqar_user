-- =============================================================================
-- Fix workflow_create_notification to match in_app_notifications schema
-- Current table uses username (not user_id/message/is_read/entity columns).
-- =============================================================================

BEGIN;

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
    created_at
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
    now()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.workflow_create_notification(uuid, text, text, text, text, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.workflow_create_notification(uuid, text, text, text, text, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.workflow_create_notification(uuid, text, text, text, text, uuid, jsonb) TO service_role;

COMMIT;
