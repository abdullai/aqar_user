-- =============================================================================
-- حذف متسلسل لعقار + مرتبطاته — مراجعة يدوية قبل التنفيذ
--
-- لا تُنفَّذ تلقائياً: يجب مواءمة أسماء الجداول والمفاتيح الأجنبية مع مخططك،
-- وتحديث سياسات RLS أو استدعاء دالة SECURITY DEFINER من لوحة التحكم.
--
-- نمط شائع: دالة واحدة `delete_property_cascade(p_property_id uuid)` تمسح
-- بالترتيب: property_images، property_media (إن وُجد)، سجلات التسويق، ثم properties.
-- أو استخدام `ON DELETE CASCADE` على FKs بعد التدقيق.
--
-- مثال هيكلي (تعليق فقط — لا يُنفَّذ هنا):
--   DELETE FROM public.property_images WHERE property_id = p;
--   DELETE FROM public.properties WHERE id = p;
--
-- راجع أيضاً: 20260346_unified_national_login_listing_numeric.sql (حذف مرتبط بسيط).
-- =============================================================================

-- placeholder: لا تضف أوامر حتى تُطابق بيئتك
SELECT 1;
