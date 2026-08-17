-- Sign-up reliability: widen duplicate checks (phone in contact_phone path),
-- harden auth.users → users_profiles bootstrap, and keep handle_new_user idempotent.
-- Fixes common Supabase error: "Database error saving new user" when a UNIQUE index
-- on normalized contact_phone/contact_email exists but pre-signup RPCs only scanned `phone`.

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Phone taken: match legacy rows that stored the same digits only in contact_phone.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.signup_phone_taken(p_phone text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH v AS (
    SELECT nullif(regexp_replace(trim(coalesce(p_phone, '')), '\D', '', 'g'), '') AS d
  )
  SELECT EXISTS (
    SELECT 1
    FROM public.users_profiles up, v
    WHERE v.d IS NOT NULL
      AND length(v.d) >= 9
      AND (
        (up.phone IS NOT NULL
          AND regexp_replace(trim(both from up.phone::text), '\D', '', 'g') = v.d)
        OR (
          up.contact_phone IS NOT NULL
          AND regexp_replace(coalesce(up.contact_phone::text, ''), '\D', '', 'g') = v.d
        )
      )
  );
$$;

-- -----------------------------------------------------------------------------
-- 2) Username / national id taken (10-digit identity) across username + national_id.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.signup_username_taken(p_username text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v text := regexp_replace(trim(coalesce(p_username, '')), '\D', '', 'g');
  by_username boolean;
BEGIN
  IF v IS NULL OR length(v) < 1 THEN
    RETURN false;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.users_profiles up
    WHERE nullif(trim(both from up.username::text), '') IS NOT NULL
      AND regexp_replace(trim(both from up.username::text), '\D', '', 'g') = v
  ) INTO by_username;

  IF by_username THEN
    RETURN true;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users_profiles'
      AND column_name = 'national_id'
  ) THEN
    RETURN EXISTS (
      SELECT 1
      FROM public.users_profiles up
      WHERE up.national_id IS NOT NULL
        AND regexp_replace(coalesce(up.national_id::text, ''), '\D', '', 'g') = v
    );
  END IF;

  RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.signup_phone_taken(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.signup_username_taken(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.signup_phone_taken(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.signup_username_taken(text) TO anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3) Bootstrap profile row on auth.users insert (SECURITY DEFINER + fixed search_path).
--    Uses user_metadata keys emitted by Flutter PasswordSetupScreen (signUp data:).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  meta jsonb := coalesce(NEW.raw_user_meta_data, '{}'::jsonb);
  un text := nullif(trim(both from coalesce(meta->>'username', '')), '');
  ph text := nullif(trim(both from coalesce(meta->>'phone', '')), '');
  em text := nullif(trim(both from coalesce(NEW.email, '')), '');
  fn text := nullif(trim(both from coalesce(meta->>'full_name', '')), '');
  atype text := coalesce(
    nullif(trim(both from coalesce(meta->>'account_type', '')), ''),
    'individual_seller'
  );
BEGIN
  IF EXISTS (SELECT 1 FROM public.users_profiles WHERE user_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  IF un IS NOT NULL THEN
    un := nullif(regexp_replace(un, '\D', '', 'g'), '');
  END IF;

  BEGIN
    INSERT INTO public.users_profiles (
      user_id,
      username,
      phone,
      email,
      account_type,
      verification_status,
      full_name
    )
    VALUES (
      NEW.id,
      un,
      ph,
      nullif(em, ''),
      atype,
      'none',
      fn
    );
  EXCEPTION
    WHEN unique_violation THEN
      NULL;
  END;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;

-- GoTrue invokes triggers in the auth context; allow calling the definer function.
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO supabase_auth_admin;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

COMMIT;
