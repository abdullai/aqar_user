-- =============================================================================
-- Diagnostics: public listing publish readiness
--
-- Shows old/current property rows and exactly why they do or do not qualify for
-- the public home feed under the current business rule:
--   owner can be individual/unverified, but the publishing marketer/business
--   must be qualified and the listing must carry media + REGA/FAL ad payload.
-- =============================================================================

WITH base AS (
  SELECT
    p.id,
    p.title,
    p.status,
    p.workflow_stage,
    p.home_feed_suppressed,
    p.owner_id,
    owner.full_name AS owner_name,
    owner.account_type AS owner_account_type,
    owner.verification_status AS owner_verification_status,
    p.published_by_marketer_id,
    marketer.full_name AS marketer_name,
    marketer.account_type AS marketer_account_type,
    marketer.verification_status AS marketer_verification_status,
    marketer.license_no AS marketer_license_no,
    public.property_has_listing_media(p.id, p.video_url) AS has_listing_media,
    public.property_marketer_public_verified(p.published_by_marketer_id) AS marketer_public_verified,
    public.property_has_rega_publish_payload_for_property(
      p.id,
      COALESCE(p.rega_payload::jsonb, '{}'::jsonb)
    ) AS has_rega_fal_payload,
    public.property_public_publish_ready(p) AS public_ready,
    public.property_license_payload(
      p.id,
      COALESCE(p.rega_payload::jsonb, '{}'::jsonb)
    ) AS license_payload,
    p.created_at,
    p.published_at
  FROM public.properties p
  LEFT JOIN public.users_profiles owner
    ON owner.user_id = p.owner_id
  LEFT JOIN public.users_profiles marketer
    ON marketer.user_id = p.published_by_marketer_id
  WHERE p.status IS DISTINCT FROM 'deleted'
)
SELECT
  id,
  title,
  status,
  workflow_stage,
  home_feed_suppressed,
  owner_name,
  owner_account_type,
  owner_verification_status,
  published_by_marketer_id,
  marketer_name,
  marketer_account_type,
  marketer_verification_status,
  marketer_license_no,
  has_listing_media,
  marketer_public_verified,
  has_rega_fal_payload,
  public_ready,
  ARRAY_REMOVE(ARRAY[
    CASE WHEN home_feed_suppressed THEN 'home_feed_suppressed_true' END,
    CASE WHEN status IS NULL OR status NOT IN (
      'published', 'active', 'available', 'live', 'reserved',
      'approved', 'listed', 'open', 'visible',
      'for_sale', 'for_rent', 'forsale', 'forrent', 'draft'
    ) THEN 'status_not_public' END,
    CASE WHEN COALESCE(workflow_stage::text, '') IN (
      'waiting_marketers',
      'marketer_selected',
      'contract_pending',
      'contract_sent',
      'contract_returned',
      'contract_signed',
      'permit_pending',
      'permit_issued',
      'inactive_72h'
    ) THEN 'internal_workflow_stage' END,
    CASE WHEN NOT has_listing_media THEN 'missing_media' END,
    CASE WHEN published_by_marketer_id IS NULL THEN 'missing_published_by_marketer_id' END,
    CASE WHEN published_by_marketer_id IS NOT NULL AND NOT marketer_public_verified THEN 'marketer_not_verified_or_missing_fal' END,
    CASE WHEN NOT has_rega_fal_payload THEN 'missing_rega_ad_or_fal_payload' END
  ], NULL) AS blocking_reasons,
  license_payload,
  created_at,
  published_at
FROM base
ORDER BY public_ready DESC, created_at DESC;
