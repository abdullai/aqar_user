-- إصلاح 401 / permission denied (42501) على RPCs بوابة ما بعد الدخول.
-- السبب: سكربت 20260429_emergency_security_hardening_phase1.sql يعمل REVOKE ALL FROM PUBLIC/anon
-- ثم GRANT لـ authenticated — إن لم تُنفَّذ بالكامل أو أُعيد إنشاء الدالة بدون GRANT تظهر 401.
-- نفّذ في Supabase → SQL Editor (آمن للتكرار).

GRANT EXECUTE ON FUNCTION public.get_active_legal_version() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_active_legal_version() TO anon;

GRANT EXECUTE ON FUNCTION public.accept_terms_v1(text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.my_org_context() TO authenticated;

GRANT EXECUTE ON FUNCTION public.my_pending_org_join_banner() TO authenticated;

GRANT EXECUTE ON FUNCTION public.register_user_device_v2(text, text, text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.clear_must_change_password_after_auth() TO authenticated;

GRANT SELECT ON public.legal_documents_versions TO authenticated;
