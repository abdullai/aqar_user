-- =============================================================================
-- Post-auth gate contract (documentation + DB comments)
-- -----------------------------------------------------------------------------
-- ترتيب التطبيق: lib/core/workflow/post_auth_gate_pipeline.dart → PostAuthShell
-- RPCs: get_active_legal_version, accept_terms_v1, register_user_device_v2,
--       ack_profile_data_revision — انظر 20260323_org_teams_legal_devices.sql
--       و 20260409_ack_profile_data_revision_rpc.sql
-- RLS على users_profiles: 20260422_users_profiles_rls_consolidated_fix.sql
--
-- ملاحظة: إن لم تُنفَّذ 20260339_org_join_repair_login_uniques_fal.sql فالأعمدة
-- أدناه تُضاف هنا بـ IF NOT EXISTS حتى لا يفشل COMMENT.
-- =============================================================================

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS fal_license_expires_at timestamptz;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS fal_compliance_hold boolean NOT NULL DEFAULT false;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS signature_storage_path text;

COMMENT ON TABLE public.users_profiles IS
  'User profile row. Post-login gate order in app (OTP → shell): '
  'legal version (terms_version_accepted vs active legal doc), must_change_password, '
  'trusted device registration (RPC), unified_national_number for marketing types, '
  'profile_data_revision ack, FAL expiry/compliance, signature_storage_path when required. '
  'See Flutter PostAuthGatePipeline.';

COMMENT ON COLUMN public.users_profiles.terms_version_accepted IS
  'Last accepted legal_documents_versions.version; compared client-side to get_active_legal_version.';

COMMENT ON COLUMN public.users_profiles.must_change_password IS
  'When true, PostAuthShell shows mandatory password change before device registration.';

COMMENT ON COLUMN public.users_profiles.unified_national_number IS
  '700-number for marketing account types; gate MandatoryDataCompletionScreen when invalid/missing.';

COMMENT ON COLUMN public.users_profiles.account_type IS
  'Drives FAL/unified-national requirements; see AccountCompletionService.accountTypeNeedsUnifiedNational.';

COMMENT ON COLUMN public.users_profiles.profile_data_revision IS
  'App forces ProfileDataRevisionGateScreen until user ack matches kAppRequiredProfileDataRevision (RPC ack_profile_data_revision).';

COMMENT ON COLUMN public.users_profiles.fal_license_expires_at IS
  'Used with fal_compliance_hold for FalRenewalGateScreen / expiry banner (ProfileComplianceService.evaluateFal).';

COMMENT ON COLUMN public.users_profiles.fal_compliance_hold IS
  'When true with expiry, PostAuthShell blocks with FalRenewalGateScreen until renewed.';

COMMENT ON COLUMN public.users_profiles.signature_storage_path IS
  'When required and empty, PostAuthShell shows ProfileSignatureGateScreen.';
