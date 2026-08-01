-- أنشئ هذه الدالة وحدها أولاً في SQL Editor ثم Run.
-- لا تلصق أي رسالة خطأ معها.

CREATE OR REPLACE FUNCTION public.auth_is_marketing_account()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $fn$
  SELECT EXISTS (
    SELECT 1
    FROM public.users_profiles up
    WHERE up.user_id = auth.uid()
      AND lower(trim(coalesce(up.account_type::text, ''))) IN (
        'marketer', 'office', 'company', 'institution', 'agency'
      )
  );
$fn$;
