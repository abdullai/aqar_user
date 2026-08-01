// lib/shared/core/supabase_schema_selects.dart
//
// PostgREST يعيد 400 إذا ذُكر عمود غير موجود في الجدول. استخدام `*` على `properties`
// يعيد فقط الأعمدة الموجودة فعلياً ويتجنب كسر الإعلانات عند تأخر migrations على Supabase.
// للصور نبقي تضمين `property_images` فقط (إن وُجدت العلاقة في المخطط).

abstract final class SupabaseSchemaSelects {
  /// فلتر عرض الإعلانات المنشورة للجمهور بدون مسارات التسويق الداخلية.
  ///
  /// يُفضَّل معه في الاستعلام: `.or('home_feed_suppressed.is.null,home_feed_suppressed.eq.false')` بعد migration
  /// `20260410_listing_report_escalation.sql` لإخفاء الإعلانات ذات البلاغات المتعددة من الرئيسية.
  static const String propertiesPublicVisibleOrFilter =
      'status.eq.published,status.eq.active,status.eq.available,status.eq.live,'
      'status.eq.reserved,status.eq.approved,status.eq.listed,status.eq.open,'
      'status.eq.visible,status.eq.for_sale,status.eq.for_rent,'
      'status.eq.forsale,status.eq.forrent';

  /// توافق قديم فقط: لا تظهر مسودات التسويق للعامة.
  ///
  /// مراحل مثل `waiting_marketers`, `marketer_selected`, `permit_pending`,
  /// و`inactive_72h` مكانها لوحات المالك/المسوق وليس الرئيسية العامة.
  static const String propertiesDraftLiveOnHomeOrFilter =
      'and(status.eq.draft,workflow_stage.in.(published,reserved))';

  /// اجمع [propertiesPublicVisibleOrFilter] مع توافق المسودات المنشورة فقط.
  static String get propertiesHomeFeedOrFilter =>
      '$propertiesPublicVisibleOrFilter,$propertiesDraftLiveOnHomeOrFilter';

  /// حالات طلبات السوق الظاهرة في الرئيسية حتى الإغلاق (يتوافق مع RLS في `20260459` وما بعده).
  static const List<String> marketPropertyRequestsHomeStatuses = [
    'published',
    'active',
    'live',
    'open',
    'visible',
    'under_review',
    'in_progress',
    'seeking',
    'bidding',
    'negotiating',
    'collecting_offers',
    'delete_requested',
  ];

  /// صفوف العقارات للرئيسية / صفحتي / السلة / المميز — مع صور.
  static const String propertiesListing = '''
*,
property_images(sort_order,path,file_name)
''';

  /// بدون تضمين `property_images` — يُستخدم عند غياب سياسة RLS للصور على Supabase
  /// (بدونها PostgREST يعيد 401 للاستعلام المضمّن وليس 200+[]).
  static const String propertiesListingWithoutImageEmbed = '*';

  /// عقارات مرتبطة بعدة طلبات (معاينة).
  static const String propertiesPreviewByRequestId = '''
*,
property_images(path,file_name,sort_order)
''';

  /// دمج طلبات listing_requests للوحة المسوق/المالك.
  ///
  /// `request_price` / `preview_price`: لحساب أتعاب التسويق (نسبة ثابتة في التطبيق من المجموع بعد ضريبة 5٪ على العقار).
  /// إن لم تكن الأعمدة مُنشأة في Supabase بعد، أزل الأسطر الناقصة لتفادي PostgREST 400
  /// (مثل owner_regulatory_ack_at بعد migration 20260465).
  static const String listingRequestsLookup = '''
id,
owner_id,
listing_request_public_code,
title,
city,
price,
request_price,
preview_price,
price_includes_vat,
vat_rate,
marketing_commission_kind,
marketing_commission_rate,
marketing_commission_amount,
default_cover_used,
description,
status,
marketer_id,
created_at,
owner_regulatory_ack_at,
updated_at,
payload,
owner_phone,
latitude,
longitude,
location,
address_line,
lat,
lng,
payload_json,
selected_offer_id,
selected_marketer_id,
contract_id,
permits_due_at,
workflow_stage,
marketing_round,
relist_count,
allow_previous_marketers_retry,
waiting_marketers_since,
contract_started_at,
contract_sent_at,
contract_signed_at,
permit_deadline_at,
inactive_72h_at,
owner_action_required_at,
owner_action_reason,
prev_selected_marketer_id,
contract_deadline_at,
auto_expired_at,
owner_viewed_offers_at,
marketing_cancel_request_at,
marketing_cancel_request_reason,
preview_property_id,
banned_under_review,
needs_manual_review,
owner_distinct_marketer_declines,
owner_contract_cancel_count,
rega_mismatch_attempts
''';
}
