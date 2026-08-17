BEGIN;

DO $$
DECLARE
  payload_type text;
BEGIN
  SELECT data_type
  INTO payload_type
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'properties'
    AND column_name = 'rega_payload';

  IF payload_type IN ('json', 'jsonb') THEN
    EXECUTE format($sql$
      UPDATE public.properties p
      SET rega_payload = (
        coalesce(p.rega_payload::jsonb, '{}'::jsonb)
        || jsonb_build_object(
          'marketer_display_name', src.display_name,
          'marketer_entity_display_name', src.display_name
        )
      )::%s
      FROM (
        SELECT
          up.user_id::text AS user_id,
          coalesce(
            nullif(trim(up.full_name_ar), ''),
            nullif(trim(up.full_name), ''),
            nullif(trim(up.full_name_en), ''),
            nullif(trim(up.username), '')
          ) AS display_name
        FROM public.users_profiles up
      ) src
      WHERE p.published_by_marketer_id::text = src.user_id
        AND src.display_name IS NOT NULL
        AND (
          p.edit_count IS NULL
          OR p.edit_count < coalesce(p.max_edits, 3)
        )
        AND nullif(trim(coalesce(
          p.rega_payload::jsonb ->> 'marketer_entity_display_name',
          p.rega_payload::jsonb ->> 'marketer_display_name',
          p.rega_payload::jsonb ->> 'marketer_office_name',
          p.rega_payload::jsonb ->> 'company_name',
          p.rega_payload::jsonb ->> 'office_name',
          ''
        )), '') IS NULL
    $sql$, payload_type);
  END IF;
END $$;

CREATE OR REPLACE VIEW public.v_aqar_properties_missing_marketer_names AS
SELECT
  p.id,
  p.owner_id,
  p.published_by_marketer_id,
  p.title,
  p.status,
  p.edit_count,
  p.max_edits
FROM public.properties p
WHERE nullif(trim(coalesce(p.published_by_marketer_id::text, '')), '') IS NOT NULL
  AND nullif(trim(coalesce(
    p.rega_payload::jsonb ->> 'marketer_entity_display_name',
    p.rega_payload::jsonb ->> 'marketer_display_name',
    p.rega_payload::jsonb ->> 'marketer_office_name',
    p.rega_payload::jsonb ->> 'company_name',
    p.rega_payload::jsonb ->> 'office_name',
    ''
  )), '') IS NULL;

COMMENT ON VIEW public.v_aqar_properties_missing_marketer_names IS
  'Published-by-marketer listings that still need a marketer display name in rega_payload; rows at edit limit may require admin repair.';

COMMIT;
