-- إصلاح بيانات v3 إذا فشلت 20260530160000 عند عمود updated_at (بدون لمس updated_at).

UPDATE public.subscription_plans
SET
  max_members = 3,
  max_ads_per_month = 60,
  max_listing_requests = NULL,
  max_properties = NULL,
  team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)
WHERE is_active = true
  AND coalesce(is_trial_plan, false) = false
  AND sort_order = 1
  AND user_type IN ('marketer','office','institution','company');

UPDATE public.subscription_plans SET
  max_members = 6, max_ads_per_month = 450, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)
WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 2 AND user_type = 'office';

UPDATE public.subscription_plans SET
  max_members = 9, max_ads_per_month = 450, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)
WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 2 AND user_type = 'institution';

UPDATE public.subscription_plans SET
  max_members = 12, max_ads_per_month = 450, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)
WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 2 AND user_type = 'company';

UPDATE public.subscription_plans SET
  max_members = 0, max_ads_per_month = 450, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)
WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 2 AND user_type = 'marketer';

UPDATE public.subscription_plans SET
  max_members = 6, max_ads_per_month = NULL, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)
WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 3 AND user_type = 'office';

UPDATE public.subscription_plans SET
  max_members = 9, max_ads_per_month = NULL, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)
WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 3 AND user_type = 'institution';

UPDATE public.subscription_plans SET
  max_members = 12, max_ads_per_month = NULL, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)
WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 3 AND user_type = 'company';

UPDATE public.subscription_plans SET
  max_members = 0, max_ads_per_month = NULL, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)
WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 3 AND user_type = 'marketer';

UPDATE public.subscription_plans SET
  max_ads_per_month = NULL,
  max_properties = NULL,
  max_listing_requests = NULL
WHERE coalesce(is_trial_plan, false) = true;
