-- =============================================================================
-- 2026-06-17 — مراجعة حدود الباقات حسب نوع المستخدم
-- =============================================================================
-- • التسويق (مسوق/مكتب/مؤسسة/شركة): إعلانات محدودة شهرياً، طلبات عقارية غير محدودة
-- • الفرد/المالك/المستخدم: إعلانات محدودة، عروض على الطلبات عبر باقات 11/12/13
-- =============================================================================

BEGIN;

-- طلبات عقارية غير محدودة لأدوار التسويق
UPDATE public.subscription_plans
   SET max_listing_requests = NULL
 WHERE user_type IN ('marketer', 'office', 'institution', 'company')
   AND coalesce(is_trial_plan, false) = false;

-- الباقة الأساسية للفرد: عضو فريق / عمل فردي — لا نشر طلبات سوق غير محدود
UPDATE public.subscription_plans
   SET max_listing_requests = NULL,
       max_market_offers = coalesce(max_market_offers, 0)
 WHERE user_type = 'individual'
   AND sort_order = 1
   AND coalesce(is_trial_plan, false) = false;

-- خصم سنوي 20% (price_yearly = شهري × 12 × 0.80) للباقات الرئيسية
UPDATE public.subscription_plans
   SET price_yearly = round(price_monthly * 12 * 0.80, 2),
       auto_pay_discount_percent = coalesce(auto_pay_discount_percent, 20)
 WHERE coalesce(is_trial_plan, false) = false
   AND sort_order IN (1, 2, 3)
   AND plan_program = 'monthly'
   AND price_monthly > 0;

COMMIT;
