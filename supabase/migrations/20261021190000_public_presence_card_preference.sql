CREATE OR REPLACE FUNCTION public.get_user_presence_summary(
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_last timestamptz;
  v_hide boolean := false;
  v_show_on_cards boolean := true;
  v_recent boolean := false;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_user_id');
  END IF;

  SELECT
    chat_last_seen_at,
    coalesce(chat_last_seen_hidden, false),
    coalesce(publish_presence_on_cards, true)
  INTO v_last, v_hide, v_show_on_cards
  FROM public.users_profiles
  WHERE user_id = p_user_id
  LIMIT 1;

  v_recent := v_show_on_cards
    AND v_last IS NOT NULL
    AND v_last > timezone('utc', now()) - interval '60 seconds';

  RETURN jsonb_build_object(
    'ok', true,
    'online_now', v_recent,
    'hidden', v_hide,
    'show_on_cards', v_show_on_cards,
    'last_seen_at', CASE
      WHEN NOT v_show_on_cards THEN NULL
      WHEN v_hide AND NOT v_recent THEN NULL
      ELSE v_last
    END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_user_presence_summary(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_presence_summary(uuid)
  TO anon, authenticated, service_role;
