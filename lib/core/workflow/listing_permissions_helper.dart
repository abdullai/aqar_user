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
    final s = _stage(property);
    if (const {
      ListingWorkflowStage.cancelled,
      ListingWorkflowStage.terminated,
      ListingWorkflowStage.archived,
      ListingWorkflowStage.contractCancelled,
      ListingWorkflowStage.waitingMarketers,
      ListingWorkflowStage.marketerSelected,
      ListingWorkflowStage.contractPending,
      ListingWorkflowStage.contractSent,
      ListingWorkflowStage.contractReturned,
      ListingWorkflowStage.contractSigned,
      ListingWorkflowStage.permitPending,
      ListingWorkflowStage.permitIssued,
      ListingWorkflowStage.inactive72h,
    }.contains(s)) {
      return false;
    }
    if (s == ListingWorkflowStage.published ||
        s == ListingWorkflowStage.reserved) {
      return true;
    }
    // مواءمة مع PostgREST: [propertiesHomeFeedOrFilter].
    // مراحل التسويق الداخلية تبقى في لوحات المالك/المسوق ولا تظهر في الرئيسية.
    if (_publicHomeStatusHints.contains(property.normalizedStatus)) return true;
    return property.isActive;
  }

  /// بطاقة إعلان في **تبويب الرئيسية** فقط: ما بعد مسلك النشر/العرض للعموم.
  /// مراحل العقود والتصاريح و«انتظار المسوّقين» تبقى في «صفحتي» ولا تُعرض في شبكة الرئيسية.
  static bool shouldShowOnHomeDiscoveryCard(Property property) {
    if (!shouldShowInPublicHome(property)) return false;
    final s = _stage(property);
    if (const {
      ListingWorkflowStage.published,
      ListingWorkflowStage.reserved,
    }.contains(s)) {
      return true;
    }
    // خمول 72 ساعة بعد إعلان منشور سابقًا — وليس معاينة draft بلا published_at.
    if (s == ListingWorkflowStage.inactive72h &&
        property.publishedAt != null &&
        !_completedDealStatusHints.contains(property.normalizedStatus)) {
      return true;
    }
    if (property.publishedAt != null &&
        !_completedDealStatusHints.contains(property.normalizedStatus)) {
      return true;
    }
    return false;
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

  static const Set<String> _publicHomeStatusHints = {
    'published',
    'active',
    'available',
    'live',
    'reserved',
    'approved',
    'listed',
    'open',
    'visible',
    'for_sale',
    'for_rent',
    'forsale',
    'forrent',
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
