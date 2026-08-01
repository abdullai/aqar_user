library user_dashboard;

// =============================
// IMPORTS
// =============================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

// project imports
import '../l10n/app_localizations.dart';
import '../core/config/app_config.dart';
import '../core/branding/app_branding.dart';
import '../core/branding/branding_logo_image.dart';
import '../core/listing/listing_media_urls.dart';
import '../core/session/app_session.dart';
import '../core/subscription/app_subscription_gate.dart';
import '../core/auth/auth_signed_out_navigation_guard.dart';
import '../core/auth/safe_sign_out_service.dart';
import '../core/navigation/app_exit_navigation.dart';
import '../core/network/supabase_interceptor.dart';
import '../core/navigation/app_web_soft_refresh.dart';
import '../core/navigation/web_dashboard_mount_guard.dart';
import '../core/navigation/web_bootstrap_diag.dart';
import '../core/navigation/web_interaction_recovery.dart';
import '../widgets/app_back_refresh_dialogs.dart';
import '../core/session/web_session_ttl.dart';
import '../models/property.dart';
import '../models/market_property_request_row.dart';
import '../models/market_property_request_priority.dart';
import '../models/home_mixed_feed_entry.dart';
import '../core/market/instant_market_request_feed.dart';
import '../core/utils/app_money.dart';
import '../core/utils/display_ids.dart';
import '../services/reservations_service.dart';
import '../services/fast_login_service.dart';
import '../services/account_completion_service.dart';

import 'add_property_page.dart' as addp;
import 'marketing_listing_entry_page.dart';
import 'property_details_page.dart' as details;
import 'property_map_discovery_page.dart';
import 'settings_page.dart';
import 'market_insights_page.dart';
import 'edit_property_page.dart';
import 'support_page.dart';
import '../core/forms/active_form_guard.dart';
import '../widgets/aqar_detail_table.dart';
import '../widgets/support_hub_tabs.dart';
import 'create_market_property_request_page.dart';
import 'marketer_request_details_page.dart';
import 'my_organization_screen.dart';
import 'owner_individual_desk_page.dart';
import 'listing_request_status_page.dart';
import 'listing_contract_chat_page.dart';
import 'owner_offers_page.dart';
import 'rega_ad_license_import_page.dart';
import 'organization_profile_screen.dart';

import '../core/share/listing_deep_link.dart';
import '../core/subscription/marketing_subscription_resume_intent.dart';
import '../core/share/listing_share_helper.dart';
import '../core/share/app_listing_links.dart';
import '../core/location/map_picker_geolocation.dart';
import '../core/utils/geo_helper.dart';
import '../core/utils/date_helper.dart';
import '../core/utils/number_helper.dart';
import '../core/utils/profile_verification_status.dart';
import '../core/input/saudi_input_formatters.dart';
import '../core/haptics/app_haptics.dart';
import '../core/gestures/app_gesture_preferences.dart';
import '../core/session/account_role_cache.dart';
import '../core/session/dashboard_greeting_cache.dart';
import '../core/motion/app_motion_policy.dart';
import '../core/motion/app_motion_widgets.dart';
import '../core/config/app_config.dart' show AppConfig, AppLayout;
import '../core/navigation/scroll_driven_bar_visibility.dart';
import '../core/theme/app_appearance_bridge.dart';
import '../theme.dart' show AqarScrollBehavior;
import '../widgets/aqar_desktop_scrollbar.dart';
import '../core/onboarding/one_time_prompt_coordinator.dart';
import '../core/onboarding/device_first_run_prefs.dart';
import '../core/utils/partner_display_name.dart';
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
import '../widgets/aqar_text_field.dart';
import '../core/utils/dashboard_greeting.dart';
import '../core/utils/listing_date_display.dart';
import '../services/user_listing_preferences_service.dart';
import '../widgets/listing_report_sheet.dart';
import '../widgets/listing_marketing_tracking_sheet.dart';
import '../widgets/listing_public_actions_menu.dart';
import '../widgets/listing_watermark_overlay.dart';
import '../widgets/user_presence_strip.dart';
import '../core/presence/presence_display_prefs.dart';
import '../widgets/inline_property_video.dart';
import '../widgets/property_video_sheet.dart';
import '../widgets/listing_workflow_progress_strip.dart';
import '../services/marketing_flow_service.dart';
import '../services/marketing_workflow_automation_service.dart';
import '../core/workflow/opportunity_grant_store.dart';
import '../services/marketing_buckets_cache.dart';
import '../services/fal_license_service.dart';
import '../services/individual_market_offer_service.dart';
import '../services/market_request_offers_service.dart';
import '../services/marketing_workflow_hub.dart';
import '../services/compliance_audit_service.dart';
import '../services/org_team_service.dart';
import '../services/org_permission_manager.dart';
import '../services/session_tracking_service.dart';
import '../services/session_manager.dart';
import '../services/inactivity_service.dart';
import '../core/network/supabase_public_read_guard.dart';
import '../services/properties_home_feed_service.dart';
import '../services/user_session_coordination_service.dart';
import '../services/presence_heartbeat_service.dart';
import '../services/guest_session_bridge.dart';
import '../services/guest_unlock_service.dart';
import '../widgets/guest_participation_gate.dart';
import '../services/subscription_service.dart';
import '../widgets/marketing_subscription_paywall_dialog.dart';
import '../services/legal_terms_prompt_service.dart';
import '../main.dart' show langNotifier, themeModeNotifier;
import '../core/utils/compound_display_name.dart';
import '../services/property_view_service.dart';
import '../services/location_hierarchy_service.dart';
import '../widgets/location_hierarchy_picker.dart';
import '../core/notifications/in_app_notifications.dart';
import '../core/notifications/hub_workflow_sound.dart';
import '../core/notifications/workflow_toast_sound.dart';
import '../core/notifications/in_app_notification_sound.dart';
import '../core/utils/saudi_ad_permit_number_patterns.dart';
import '../core/utils/users_profiles_safe_select.dart';
import '../core/payment/payment_input_utils.dart' show normalizeWesternDigits;
import '../services/in_app_notification_hub.dart';
import '../core/workflow/listing_workflow_copy.dart';
import '../shared/core/supabase_schema_selects.dart';
import '../core/listing/property_listing_display.dart';
import '../widgets/listing_hero_thumb.dart';
import '../core/listing/property_type_catalog.dart';
import '../core/marketing/marketer_market_visibility_prefs.dart';
import '../core/marketing/marketing_offer_fee.dart';
import '../core/marketing/marketing_workflow_ui_config.dart';
import '../widgets/marketing_offer_submit_sheet.dart';
import '../widgets/rega_ad_license_gate_sheet.dart';
import '../widgets/market_request_home_sheet.dart';
import '../widgets/market_offer_paywall_dialog.dart';
import '../widgets/subscription_gate_alert_chip.dart';
import '../widgets/instant_market_request_badge.dart';
import '../widgets/market_request_lead_thumb.dart';
import '../widgets/card_image_pulse_badge.dart';
import '../widgets/listing_formatted_spec_panel.dart';
import '../widgets/listing_request_spec_panel.dart';
import '../widgets/unified_real_estate_card.dart';
import '../widgets/aqar_money_range_field.dart';
import '../core/branding/aqar_brand_colors.dart';
import '../widgets/government_in_app_web_page.dart';
import '../widgets/dashboard_onboarding_overlay.dart';
import '../widgets/accent_color_dialog.dart';
import '../widgets/legal_terms_ack_dialog.dart';
import '../widgets/app_about_credits.dart';
import '../widgets/org_license_badge.dart';
import '../widgets/market_request_public_actions_menu.dart';
import '../routes.dart';
import '../navigation/chat_navigation.dart';
import 'chat_page.dart' show ConversationKind;
import 'marketing/marketer_market_offer_hub_page.dart';
import '../core/marketing/marketer_owner_chat_intro_ar.dart';
import '../core/notifications/app_sound_coordinator.dart';
import 'communication_hub_page.dart';
import 'reports_dashboard_screen.dart';
import 'subscriptions/subscriptions_root_screen.dart';

// =============================
// PART FILES
// =============================

part 'user_dashboard.state.dart';
part 'user_dashboard.filters.dart';
part 'user_dashboard.loaders.dart';
part 'user_dashboard.actions.dart';
part 'user_dashboard.ext.model_helpers.dart';
part 'user_dashboard.ext.ui_helpers.dart';
part 'user_dashboard.ext.bodies.dart';
part 'user_dashboard.ext.notifications.dart';
part 'user_dashboard.ext.chat.dart';
part 'user_dashboard.widgets.dart';
part 'user_dashboard.marketing_state.dart';
part 'user_dashboard.marketing_loaders.dart';
part 'user_dashboard.my_ads_hub.dart';
part 'user_dashboard.ui.dart';

// JSON decode for city lists — runs in [compute] on web (keeps UI thread free).
dynamic decodeDashboardJsonString(String raw) => json.decode(raw);

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
