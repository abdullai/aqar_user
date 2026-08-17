import '../../models/property.dart';
import 'listing_workflow_stage.dart';

/// قواعد تعديل جسم الإعلان (الواجهة + يُفضّل مطابقتها مع RLS على `properties`).
abstract final class ListingEditPermissions {
  static bool _publishedLike(Property p) {
    final st = p.normalizedStatus;
    if (p.publishedAt != null) return true;
    return const {
      'published',
      'active',
      'live',
      'available',
      'approved',
    }.contains(st);
  }

  /// المالك يعدّل حتى قبل دخول الإعلان مرحلة/تبويب إصدار التصاريح؛ مع حدود `edit_count`.
  static bool ownerMayEditListingBody(Property p) {
    if (p.isDeletedLike) return false;
    if (_publishedLike(p)) return false;
    if (p.editExhausted) return false;

    final stage = p.effectiveWorkflowStage;
    const blocked = <ListingWorkflowStage>{
      ListingWorkflowStage.permitPending,
      ListingWorkflowStage.permitIssued,
      ListingWorkflowStage.published,
      ListingWorkflowStage.reserved,
      ListingWorkflowStage.cancelled,
      ListingWorkflowStage.terminated,
      ListingWorkflowStage.archived,
      ListingWorkflowStage.contractCancelled,
      ListingWorkflowStage.inactive72h,
    };
    if (blocked.contains(stage)) return false;
    return true;
  }

  /// المسوّق المختار/المنشّر بعد إصدار التصريح وقبل النشر — لمطابقة بيانات الهيئة.
  static bool marketerMayAlignWithRega(Property p, String marketerUserId) {
    final uid = marketerUserId.trim();
    if (uid.isEmpty) return false;
    if (_publishedLike(p)) return false;
    if (p.permitIssuedAt == null) return false;

    final sel = (p.selectedMarketerId ?? '').trim();
    final pub = (p.publishedByMarketerId ?? '').trim();
    if (uid != sel && uid != pub) return false;

    final stage = p.effectiveWorkflowStage;
    return stage == ListingWorkflowStage.permitPending ||
        stage == ListingWorkflowStage.permitIssued;
  }
}
