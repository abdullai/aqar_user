-- إعادة تأكيد صلاحيات RPC الشروط (آمنة ومتكررة التشغيل).
-- نفّذها إذا كان التطبيق يفشل في استدعاء get_active_legal_version أو accept_terms_v1
-- رغم وجود التعريفات في 20260323_org_teams_legal_devices.sql.

GRANT EXECUTE ON FUNCTION public.get_active_legal_version() TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_terms_v1(text) TO authenticated;
GRANT SELECT ON public.legal_documents_versions TO authenticated;
