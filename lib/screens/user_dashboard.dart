library user_dashboard;

// =============================
// IMPORTS
// =============================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

// project imports
import '../l10n/app_localizations.dart';
import '../core/session/app_session.dart';
import '../core/session/web_session_ttl.dart';
import '../models/property.dart';
import '../models/market_property_request_row.dart';
import '../models/market_property_request_priority.dart';
import '../models/home_mixed_feed_entry.dart';
import '../core/utils/app_money.dart';
import '../core/utils/display_ids.dart';
import '../services/reservations_service.dart';
import '../services/fast_login_service.dart';

import 'add_property_page.dart' as addp;
import 'property_details_page.dart' as details;
import 'settings_page.dart';
import 'market_insights_page.dart';
import 'edit_property_page.dart';
import 'support_page.dart';
import 'create_market_property_request_page.dart';
import 'marketer_dashboard_page.dart';
import 'marketer_request_details_page.dart';
import 'my_desk_org_shell_page.dart';
import 'owner_individual_desk_page.dart';
import 'listing_request_status_page.dart';
import 'listing_contract_chat_page.dart';
import 'owner_offers_page.dart';
import 'rega_ad_license_import_page.dart';
import 'property_map_discovery_page.dart';

import '../core/share/listing_deep_link.dart';
import '../core/share/listing_share_helper.dart';
import '../core/share/app_listing_links.dart';
import '../core/location/map_picker_geolocation.dart';
import '../core/utils/geo_helper.dart';
import '../core/utils/date_helper.dart';
import '../core/utils/number_helper.dart';
import '../core/input/saudi_input_formatters.dart';
import '../core/haptics/app_haptics.dart';
import '../core/gestures/app_gesture_preferences.dart';
import '../core/session/account_role_cache.dart';
import '../core/config/app_config.dart' show AppConfig, AppLayout;
import '../core/theme/app_appearance_bridge.dart';
import '../core/onboarding/one_time_prompt_coordinator.dart';
import '../core/workflow/listing_workflow.dart';
import '../core/workflow/app_role_helper.dart';
import '../core/workflow/listing_permissions_helper.dart';
import '../core/workflow/listing_stage_ui_helper.dart';
import '../core/workflow/listing_post_publish_ui_helper.dart';
import '../core/workflow/listing_workflow_stage.dart';
import '../core/workflow/listing_edit_permissions.dart';
import '../core/workflow/listing_workflow_unified.dart';
import '../core/workflow/listing_workflow_ui_context.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_shimmer.dart';
import '../widgets/app_confirm_dialog.dart';
import '../core/utils/dashboard_greeting.dart';
import '../core/utils/listing_date_display.dart';
import '../services/user_listing_preferences_service.dart';
import '../widgets/listing_report_sheet.dart';
import '../widgets/listing_public_actions_menu.dart';
import '../widgets/listing_watermark_overlay.dart';
import '../widgets/user_presence_strip.dart';
import '../widgets/inline_property_video.dart';
import '../widgets/property_video_sheet.dart';
import '../widgets/listing_workflow_progress_strip.dart';
import '../services/marketing_flow_service.dart';
import '../services/fal_license_service.dart';
import '../services/marketing_workflow_hub.dart';
import '../services/org_team_service.dart';
import '../services/legal_terms_prompt_service.dart';
import '../services/property_view_service.dart';
import '../core/notifications/in_app_notifications.dart';
import '../services/in_app_notification_hub.dart';
import '../core/workflow/listing_workflow_copy.dart';
import '../shared/core/supabase_schema_selects.dart';
import '../core/listing/property_listing_display.dart';
import '../core/listing/property_type_catalog.dart';
import '../core/marketing/marketing_offer_fee.dart';
import '../widgets/marketing_offer_submit_sheet.dart';
import '../widgets/marketing_full_scenario_sheet.dart';
import '../widgets/rega_ad_license_gate_sheet.dart';
import '../widgets/market_request_home_sheet.dart';
import '../widgets/market_request_lead_thumb.dart';
import '../widgets/unified_real_estate_card.dart';
import '../widgets/dashboard_onboarding_overlay.dart';
import '../widgets/accent_color_dialog.dart';
import '../routes.dart';
import '../navigation/chat_navigation.dart';
import 'communication_hub_page.dart';

// =============================
// PART FILES
// =============================

part 'user_dashboard.state.dart';
part 'user_dashboard.filters.dart';
part 'user_dashboard.loaders.dart';
part 'user_dashboard.actions.dart';
part 'user_dashboard.ext.model_helpers.dart';
part 'user_dashboard.ext.ui_helpers.dart';
part 'user_dashboard.ext.build.dart';
part 'user_dashboard.ext.bodies.dart';
part 'user_dashboard.ext.notifications.dart';
part 'user_dashboard.ext.chat.dart';
part 'user_dashboard.widgets.dart';
part 'user_dashboard.marketing_state.dart';
part 'user_dashboard.marketing_loaders.dart';
part 'user_dashboard.my_ads_hub.dart';
part 'user_dashboard.ui.dart';

// =============================
// GLOBAL CONSTANTS
// =============================

/// ترتيب ثابت للشريط السفلي (يتم تخطي عناصر حسب الصلاحية).
enum DashboardBottomSlot {
  home,
  myAds,

  /// طلباتي: إعلانات وطلبات سوق قدّمها المستخدم (بطاقات كالرئيسية).
  mySubmissions,
  addListing,
  myDesk,
  cart,

  /// الدعم الفني + قنوات الإدارة (المحادثات من أيقونة الجرس).
  support,
}

/// فلتر شريط الرئيسية: إعلانات و/أو طلبات السوق (تبويب علوي، بدون تبويب سفلي إضافي).
enum HomeFeedKind {
  /// إعلانات + طلبات منشورة في تسليمة واحدة.
  all,

  /// عقارات فقط.
  listings,

  /// طلبات السوق فقط.
  requests,
}
