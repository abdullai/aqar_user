-- صلاحيات/هوية الحسابين + هل يفترض أن يريا السوق المفتوح؟
SELECT
  username,
  account_type,
  user_id,
  CASE
    WHEN lower(trim(account_type::text)) IN (
      'marketer', 'office', 'company', 'institution', 'agency'
    ) THEN 'نعم — حساب تسويقي (يرى السوق المفتوح لطلبات غيره)'
    ELSE 'لا'
  END AS can_see_open_market_by_role
FROM public.users_profiles
WHERE username IN ('1010101011', '1073743757', '1000000000');

-- هل هما مالكا منشأة أم أعضاء فريق؟
SELECT
  up.username,
  up.account_type,
  ou.id AS org_id,
  ou.owner_user_id,
  (ou.owner_user_id = up.user_id) AS is_org_owner,
  om.member_role,
  om.status AS membership_status,
  om.permissions
FROM public.users_profiles up
LEFT JOIN public.org_units ou
  ON ou.owner_user_id = up.user_id
  OR ou.id::text = up.org_id::text
LEFT JOIN public.org_memberships om
  ON om.user_id = up.user_id
 AND (om.org_id = ou.id OR om.org_id::text = up.org_id::text)
WHERE up.username IN ('1010101011', '1073743757');
