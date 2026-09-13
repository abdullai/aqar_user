import '../../models/market_property_request_row.dart';
import '../../models/property.dart';
import 'app_role_helper.dart';
import 'listing_workflow_stage.dart';

/// Central policy for CTAs — do not duplicate conditions in widgets.
class ListingPermissionsHelper {
  ListingPermissionsHelper._();

  static ListingWorkflowStage _stage(Property p) => p.effectiveWorkflowStage;

  static bool canSubmitOffer({
    required Property property,
    required String? currentUserId,
    required bool isGuest,
    required String? accountType,
    required bool marketerVerified,
    required bool hasOfferThisRound,
    required bool isExcludedWithoutRetry,
  }) {
    if (isGuest || currentUserId == null || currentUserId.isEmpty) return false;
    if (!AppRoleHelper.isVerifiedMarketerRole(accountType,
        verified: marketerVerified)) {
      return false;
    }
    if (property.ownerId == currentUserId) return false;
    if (_stage(property) != ListingWorkflowStage.waitingMarketers) return false;
    if (hasOfferThisRound) return false;
    if (isExcludedWithoutRetry) return false;
    return true;
  }

  static bool canAcceptOffer({
    required Property property,
    required String? currentUserId,
    required bool hasActionableOffers,
  }) {
    if (currentUserId == null || property.ownerId != currentUserId)
      return false;
    if (_stage(property) != ListingWorkflowStage.waitingMarketers) return false;
    return hasActionableOffers;
  }

  static bool canCreateContract({
    required Property property,
    required String? currentUserId,
  }) {
    if (currentUserId == null) return false;
    if (property.selectedMarketerId != currentUserId) return false;
    return const {
      ListingWorkflowStage.marketerSelected,
      ListingWorkflowStage.contractPending,
      ListingWorkflowStage.contractReturned,
    }.contains(_stage(property));
  }

  static bool canEnterPermitDetails({
    required Property property,
    required String? currentUserId,
  }) {
    if (currentUserId == null) return false;
    return property.selectedMarketerId == currentUserId &&
        _stage(property) == ListingWorkflowStage.permitPending;
  }

  /// بلاغ من الزائر: فقط للإعلانات في وضع ظهور عام نموذجي (نشر/حجز مؤقت).
  /// يُستبعد مسارات العقد والتصاريح وما قبل النشر حتى لا تُستَخدم البلاغات لتعطيل سير العمل.
  static bool shouldOfferPublicListingReport(Property property) {
    if (property.isDeletedLike) return false;
    final s = _stage(property);
    return s == ListingWorkflowStage.published ||
        s == ListingWorkflowStage.reserved;
  }

  static bool shouldShowInPublicHome(Property property) {
    if (property.isDeletedLike) return false;
    if (property.homeFeedSuppressed) return false;
    if (_completedDealStatusHints.contains(property.normalizedStatus)) {
      return false;
    }
    final wf = (property.workflowStage ?? '').trim().toLowerCase();
    if (const {
      'waiting_marketers',
      'added_by_owner',
      'marketer_selected',
      'contract_pending',
      'contract_sent',
      'contract_returned',
      'contract_signed',
      'permit_pending',
      'permit_issued',
      'inactive_72h',
      'inactive72h',
      'owner_action_required',
      'offers_received',
      'draft',
      'cancelled',
      'terminated',
      'archived',
      'contract_cancelled',
    }.contains(wf)) {
      return false;
    }
    final s = _stage(property);
    return s == ListingWorkflowStage.published ||
        s == ListingWorkflowStage.reserved;
  }

  /// بطاقة إعلان في **تبويب الرئيسية** — مطابقة لاستعلام الخادم
  /// ([propertiesHomeFeedOrFilter] + [shouldShowInPublicHome]).
  static bool shouldShowOnHomeDiscoveryCard(Property property) {
    return shouldShowInPublicHome(property);
  }

  /// حالات تعني انتهاء الصفقة / إخراج الإعلان من الرئيسية حتى لو بقي workflow قديماً.
  static const Set<String> _completedDealStatusHints = {
    'sold',
    'completed',
    'fulfilled',
    'transferred',
    'settled',
    'closed',
    'done',
    'purchased',
  };

  /// طلبات السوق الظاهرة للجميع — دفاع إضافي عن أخطاء الصف أو بيانات قديمة.
  static bool shouldShowMarketRequestInPublicHome(String? statusRaw) {
    final s = (statusRaw ?? '').trim().toLowerCase();
    if (s.isEmpty) return true;
    return !const {
      'closed',
      'deleted',
      'draft',
      'cancelled',
      'archived',
      'fulfilled',
      'completed',
      'sold',
    }.contains(s);
  }

  /// طلب سوق بلا صفقة نشطة — للضيف والمستخدمين في الرئيسية.
  static bool shouldShowMarketRequestWithoutDeal(
    MarketPropertyRequestRow r,
  ) {
    if (!shouldShowMarketRequestInPublicHome(r.status)) return false;
    if ((r.selectedOfferId ?? '').trim().isNotEmpty) return false;
    if (r.completedAt != null) return false;
    return true;
  }

  static bool canAddToCart({
    required Property property,
    required String? currentUserId,
    required bool isGuest,
    required bool showCartNavSlot,
  }) {
    if (isGuest || !showCartNavSlot) return false;
    if (currentUserId == null || currentUserId.isEmpty) return false;
    // الحجز عبر السلة لا يُستخدم مع المزاد — المزايدة من صفحة التفاصيل.
    if (property.isAuction) return false;
    if (_stage(property) != ListingWorkflowStage.published) return false;
    if (property.ownerId == currentUserId) return false;
    if (property.selectedMarketerId == currentUserId) return false;
    if (property.publishedByMarketerId == currentUserId) return false;
    return true;
  }

  /// زر «إتمام الصفقة» على بطاقة الإعلان في الرئيسية — يظهر للضيف أيضاً (يفتح الدخول).
  static bool shouldShowHomeListingDealButton({
    required Property property,
    required String? currentUserId,
    required bool isGuest,
  }) {
    if (property.isAuction) return false;
    if (_stage(property) != ListingWorkflowStage.published) return false;
    if (isGuest || currentUserId == null || currentUserId.isEmpty) return true;
    if (property.ownerId == currentUserId) return false;
    if (property.selectedMarketerId == currentUserId) return false;
    if (property.publishedByMarketerId == currentUserId) return false;
    return true;
  }

  /// زر «مزايدة» على البطاقة: يفتح التفاصيل حيث `place_property_bid`.
  static bool canOpenBidFromHomeCard({
    required Property property,
    required String? currentUserId,
    required bool isGuest,
  }) {
    if (!property.isAuction) return false;
    if (isGuest || currentUserId == null || currentUserId.isEmpty) return false;
    if (_stage(property) != ListingWorkflowStage.published) return false;
    if (property.ownerId == currentUserId) return false;
    if (property.selectedMarketerId == currentUserId) return false;
    if (property.publishedByMarketerId == currentUserId) return false;
    return true;
  }

  /// مزايدة على بطاقة الرئيسية للضيف (نفس مسار الطلب: يظهر الزر ويطلب الدخول).
  static bool shouldShowHomeListingBidButton({
    required Property property,
    required String? currentUserId,
    required bool isGuest,
  }) {
    if (!property.isAuction) return false;
    if (_stage(property) != ListingWorkflowStage.published) return false;
    if (isGuest || currentUserId == null || currentUserId.isEmpty) return true;
    if (property.ownerId == currentUserId) return false;
    if (property.selectedMarketerId == currentUserId) return false;
    if (property.publishedByMarketerId == currentUserId) return false;
    return true;
  }

  static bool canRelistProperty({
    required Property property,
    required String? currentUserId,
  }) {
    if (currentUserId == null || property.ownerId != currentUserId)
      return false;
    return const {
      ListingWorkflowStage.inactive72h,
      ListingWorkflowStage.cancelled,
      ListingWorkflowStage.terminated,
    }.contains(_stage(property));
  }
}
