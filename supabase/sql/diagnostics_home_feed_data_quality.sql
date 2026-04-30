-- =============================================================================
-- تشخيص: هل بيانات الجداول متوافقة مع سياسة الرئيسية + تقريب «بطاقات الاكتشاف»؟
-- =============================================================================
-- شغّل في Supabase → SQL Editor (صلاحيات postgres / service role).
--
-- يطابق سياسة الحزمة: supabase/sql/20260470_bundle_home_feed_rls_apply_all.sql
-- تقريب بطاقات الرئيسية (شبكة الإعلانات): listing_permissions_helper.dart
--   shouldShowOnHomeDiscoveryCard — مُبسّط في SQL أدناه.
--
-- بعد النتائج: عدّل يدوياً UPDATE/DELETE بحذر، أو صحّح workflow/status ثم أعد التشغيل.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- أ) هل RLS مفعّل؟ وهل توجد سياسة الرئيسية؟
-- -----------------------------------------------------------------------------
SELECT c.relname AS table_name,
       c.relrowsecurity AS rls_enabled
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('properties', 'market_property_requests');

SELECT tablename, policyname, roles::text, cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('properties', 'market_property_requests')
  AND cmd = 'SELECT'
ORDER BY tablename, policyname;

-- -----------------------------------------------------------------------------
-- ب) تعريف منطق السياسة الحالي للعقارات (مطابق 20260470)
-- -----------------------------------------------------------------------------
-- استخدمنا دالة مضمنة في الاستعلامات التالية عبر نفس الشرط.

-- -----------------------------------------------------------------------------
-- ج) عقارات: عدّ الصفوف حسب «دلو» مختلف (لتفسير الرئيسية)
-- -----------------------------------------------------------------------------

-- ج1) كل ما ليس deleted (خام)
SELECT COUNT(*) AS properties_all_non_deleted
FROM public.properties
WHERE status IS DISTINCT FROM 'deleted';

-- ج2) ما يمرّ بسياسة الرئيسية الحالية (ما يستطيع anon رؤيته إن وُجدت السياسة فقط دون سياسات أخرى)
SELECT COUNT(*) AS properties_pass_home_rls_policy
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
  AND COALESCE(p.home_feed_suppressed, false) = false
  AND (
    p.status IN (
      'published', 'active', 'available', 'live', 'reserved', 'approved',
      'listed', 'open', 'visible', 'for_sale', 'for_rent',
      'forsale', 'forrent',
      'pending', 'under_review', 'in_review', 'review', 'processing', 'ready', 'verified'
    )
    OR (
      p.status = 'draft'
      AND p.workflow_stage::text IN (
        'waiting_marketers',
        'marketer_selected',
        'contract_pending',
        'contract_sent',
        'contract_returned',
        'contract_signed',
        'permit_pending',
        'permit_issued',
        'published',
        'reserved',
        'inactive_72h'
      )
    )
  );

-- ج3) معطّلة من الرئيسية صراحةً
SELECT COUNT(*) AS properties_home_feed_suppressed_true
FROM public.properties
WHERE status IS DISTINCT FROM 'deleted'
  AND COALESCE(home_feed_suppressed, false) = true;

-- ج4) تقريب «بطاقة اكتشاف» في التطبيق (إعلان منشور/ظاهر للعموم — ليس كل مسار المسودة)
--     ليس مطابقاً حرفياً لـ Dart (effectiveWorkflowStage) لكنه يكشف الغالبية.
SELECT COUNT(*) AS properties_approx_home_discovery_cards
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
  AND COALESCE(p.home_feed_suppressed, false) = false
  AND LOWER(COALESCE(p.status::text, '')) NOT IN (
    'sold', 'completed', 'fulfilled', 'transferred', 'settled', 'closed', 'done', 'purchased', 'deleted'
  )
  AND LOWER(COALESCE(p.workflow_stage::text, '')) NOT IN (
    'cancelled', 'terminated', 'archived', 'contract_cancelled'
  )
  AND (
    LOWER(COALESCE(p.workflow_stage::text, '')) IN ('published', 'reserved')
    OR (
      LOWER(COALESCE(p.workflow_stage::text, '')) = 'inactive_72h'
      AND p.published_at IS NOT NULL
    )
    OR (
      p.published_at IS NOT NULL
      AND LOWER(COALESCE(p.status::text, '')) NOT IN (
        'sold', 'completed', 'fulfilled', 'transferred', 'settled', 'closed', 'done', 'purchased'
      )
    )
  );

-- ج5) يمرّ بالسياسة لكنه ليس ضمن «بطاقة اكتشاف» (مسودات مسار — تظهر في استعلام PostgREST ويُخفى في واجهة الرئيسية)
SELECT COUNT(*) AS properties_in_api_pool_but_not_discovery_card
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
  AND COALESCE(p.home_feed_suppressed, false) = false
  AND (
    p.status IN (
      'published', 'active', 'available', 'live', 'reserved', 'approved',
      'listed', 'open', 'visible', 'for_sale', 'for_rent',
      'forsale', 'forrent',
      'pending', 'under_review', 'in_review', 'review', 'processing', 'ready', 'verified'
    )
    OR (
      p.status = 'draft'
      AND p.workflow_stage::text IN (
        'waiting_marketers',
        'marketer_selected',
        'contract_pending',
        'contract_sent',
        'contract_returned',
        'contract_signed',
        'permit_pending',
        'permit_issued',
        'published',
        'reserved',
        'inactive_72h'
      )
    )
  )
  AND NOT (
    LOWER(COALESCE(p.status::text, '')) NOT IN (
      'sold', 'completed', 'fulfilled', 'transferred', 'settled', 'closed', 'done', 'purchased', 'deleted'
    )
    AND LOWER(COALESCE(p.workflow_stage::text, '')) NOT IN (
      'cancelled', 'terminated', 'archived', 'contract_cancelled'
    )
    AND (
      LOWER(COALESCE(p.workflow_stage::text, '')) IN ('published', 'reserved')
      OR (
        LOWER(COALESCE(p.workflow_stage::text, '')) = 'inactive_72h'
        AND p.published_at IS NOT NULL
      )
      OR (
        p.published_at IS NOT NULL
        AND LOWER(COALESCE(p.status::text, '')) NOT IN (
          'sold', 'completed', 'fulfilled', 'transferred', 'settled', 'closed', 'done', 'purchased'
        )
      )
    )
  );

-- ج6) عينة: صفوف «تبدو منشورة» لكن workflow_stage غير published (قديمة — راجع يدوياً)
SELECT p.id, p.title, p.status, p.workflow_stage::text AS workflow_stage, p.published_at, p.updated_at
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
  AND COALESCE(p.home_feed_suppressed, false) = false
  AND LOWER(COALESCE(p.status::text, '')) IN ('active', 'published', 'available', 'live')
  AND LOWER(COALESCE(p.workflow_stage::text, '')) NOT IN ('published', 'reserved', 'inactive_72h')
ORDER BY p.updated_at DESC
LIMIT 30;

-- -----------------------------------------------------------------------------
-- د) طلبات السوق: حسب الحالة — ما يدخل فلتر التطبيق مقابل ما خارجه
-- -----------------------------------------------------------------------------
SELECT COALESCE(status, '(null)') AS status, COUNT(*)::bigint AS cnt
FROM public.market_property_requests
GROUP BY 1
ORDER BY cnt DESC;

SELECT COUNT(*) AS market_requests_in_app_home_whitelist
FROM public.market_property_requests r
WHERE r.status IN (
  'published', 'active', 'live', 'open', 'visible',
  'under_review', 'in_progress', 'seeking', 'bidding',
  'negotiating', 'collecting_offers'
);

SELECT r.id, r.title, r.status, r.city, r.created_at
FROM public.market_property_requests r
WHERE r.status IS NOT NULL
  AND r.status NOT IN (
    'published', 'active', 'live', 'open', 'visible',
    'under_review', 'in_progress', 'seeking', 'bidding',
    'negotiating', 'collecting_offers'
  )
ORDER BY r.created_at DESC
LIMIT 50;

-- -----------------------------------------------------------------------------
-- هـ) ماذا يرى دور anon؟ (إن فشل SET ROLE: نفّذ كمشرف: GRANT anon TO postgres;)
-- -----------------------------------------------------------------------------
SET ROLE anon;
SELECT
  (
    SELECT COUNT(*)::bigint
    FROM public.properties p
    WHERE p.status IS DISTINCT FROM 'deleted'
      AND COALESCE(p.home_feed_suppressed, false) = false
      AND (
        p.status IN (
          'published', 'active', 'available', 'live', 'reserved', 'approved',
          'listed', 'open', 'visible', 'for_sale', 'for_rent',
          'forsale', 'forrent',
          'pending', 'under_review', 'in_review', 'review', 'processing', 'ready', 'verified'
        )
        OR (
          p.status = 'draft'
          AND p.workflow_stage::text IN (
            'waiting_marketers',
            'marketer_selected',
            'contract_pending',
            'contract_sent',
            'contract_returned',
            'contract_signed',
            'permit_pending',
            'permit_issued',
            'published',
            'reserved',
            'inactive_72h'
          )
        )
      )
  ) AS properties_visible_as_anon,
  (
    SELECT COUNT(*)::bigint
    FROM public.market_property_requests r
    WHERE r.status IN (
      'published', 'active', 'live', 'open', 'visible',
      'under_review', 'in_progress', 'seeking', 'bidding',
      'negotiating', 'collecting_offers'
    )
  ) AS market_requests_visible_as_anon;
RESET ROLE;

-- =============================================================================
-- ز) أمثلة تعديل يدوي (مُعلّقة — راجع WHERE ثم شغّل سطراً سطراً)
-- =============================================================================
-- -- إعلان «نشط» لكن المرحلة قديمة: ضبط للنشر (مثال — لا تشغّل على إنتاج دون مراجعة):
-- UPDATE public.properties
-- SET workflow_stage = 'published', updated_at = now()
-- WHERE id = 'PUT-UUID-HERE'
--   AND status = 'active'
--   AND published_at IS NOT NULL;
--
-- -- إخفاء إعلان من الرئيسية دون حذف:
-- UPDATE public.properties
-- SET home_feed_suppressed = true, updated_at = now()
-- WHERE id = 'PUT-UUID-HERE';
--
-- -- طلب سوق بحالة غير مدرجة في RLS: إن كان مقصوداً للظهور غيّر إلى published:
-- UPDATE public.market_property_requests
-- SET status = 'published', updated_at = now()
-- WHERE id = 'PUT-UUID-HERE';
