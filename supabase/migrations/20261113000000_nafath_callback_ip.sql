BEGIN;

-- Retain the IP supplied for the original request for audit and provider headers.
ALTER TABLE public.nafath_logins
  ADD COLUMN IF NOT EXISTS client_ip inet;

COMMIT;
