-- أسماء جهات النشر الظاهرة على بطاقات الرئيسية للضيف والمسجّل
-- (بدون فتح users_profiles أمام anon).

BEGIN;

CREATE OR REPLACE FUNCTION public.get_listing_publisher_card_labels(
  p_user_ids uuid[]
)
RETURNS TABLE (
  user_id uuid,
  display_label text,
  entity_kind text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_ids IS NULL OR cardinality(p_user_ids) = 0 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    up.user_id,
    nullif(
      trim(
        CASE
          WHEN coalesce(up.account_type::text, '') ~*
               '(office|agency|company|organization|institution|establishment|مكتب|شركة|مؤسسة|business)'
            OR nullif(trim(coalesce(up.office_name, '')), '') IS NOT NULL
          THEN coalesce(
            nullif(trim(up.office_name), ''),
            nullif(trim(up.display_name), ''),
            nullif(trim(up.full_name_ar), ''),
            nullif(trim(up.full_name), ''),
            nullif(trim(up.full_name_en), ''),
            nullif(trim(up.username), '')
          )
          WHEN coalesce(up.public_name_source, 'official') = 'display'
            AND nullif(trim(coalesce(up.display_name, '')), '') IS NOT NULL
          THEN trim(up.display_name)
          ELSE coalesce(
            nullif(
              trim(
                concat_ws(
                  ' ',
                  nullif(trim(up.first_name_ar), ''),
                  nullif(trim(up.second_name_ar), ''),
                  nullif(trim(up.third_name_ar), ''),
                  nullif(trim(up.fourth_name_ar), '')
                )
              ),
              ''
            ),
            nullif(trim(up.full_name_ar), ''),
            nullif(trim(up.full_name), ''),
            nullif(
              trim(
                concat_ws(
                  ' ',
                  nullif(trim(up.first_name_en), ''),
                  nullif(trim(up.second_name_en), ''),
                  nullif(trim(up.third_name_en), ''),
                  nullif(trim(up.fourth_name_en), '')
                )
              ),
              ''
            ),
            nullif(trim(up.full_name_en), ''),
            nullif(trim(up.display_name), ''),
            nullif(trim(up.username), '')
          )
        END
      ),
      ''
    ) AS display_label,
    CASE
      WHEN coalesce(up.account_type::text, '') ~* '(company|شركة)' THEN 'company'
      WHEN coalesce(up.account_type::text, '') ~*
           '(institution|establishment|مؤسسة)' THEN 'institution'
      WHEN coalesce(up.account_type::text, '') ~*
           '(office|agency|organization|مكتب|business)'
        OR nullif(trim(coalesce(up.office_name, '')), '') IS NOT NULL
      THEN 'office'
      ELSE 'marketer'
    END AS entity_kind
  FROM public.users_profiles up
  WHERE up.user_id = ANY (p_user_ids);
END;
$$;

REVOKE ALL ON FUNCTION public.get_listing_publisher_card_labels(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_listing_publisher_card_labels(uuid[])
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_listing_publisher_card_labels(uuid[]) IS
  'Public card labels for listing publishers (marketer quad name or office/company/establishment). Safe for anon.';

COMMIT;
