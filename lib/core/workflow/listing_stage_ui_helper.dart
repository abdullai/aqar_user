import 'package:flutter/material.dart';

import 'listing_workflow_stage.dart';

/// Owner hub — فلترة الطلبات/العقارات عبر [ownerTabMatches] بمؤشرات داخلية:
/// 0 انتظار مسوّقين، 1 التعاقد (بعد الموافقة حتى التصريح)، 2 توقف 72س، 3 ملغى، 4 محجوز، 5 منشور، 6 مكتمل.
/// شريط التبويب في الواجهة (0..6) يضيف «العروض المقدمة» — انظر `ownerHubDisplayTabIndex`.
/// Marketer hub tabs (داخل «صفحتي») — indices 0..6:
/// 0 سوق، 1 عروضي، 2 تعاقد/موافقة، 3 تصريح 72س، 4 منشور/محجوز، 5 بدون إجراء 72، 6 مفسوخ.
class ListingStageUiHelper {
  ListingStageUiHelper._();

  static const _ownerPostApprovalStages = {
    ListingWorkflowStage.marketerSelected,
    ListingWorkflowStage.contractPending,
    ListingWorkflowStage.contractSent,
    ListingWorkflowStage.contractReturned,
    ListingWorkflowStage.contractSigned,
    ListingWorkflowStage.permitPending,
    ListingWorkflowStage.permitIssued,
  };

  /// مراحل تبويب «التعاقد» فقط (بدون التصريح — له تبويب مستقل index 3).
  static const _marketerContractingStages = {
    ListingWorkflowStage.marketerSelected,
    ListingWorkflowStage.contractPending,
    ListingWorkflowStage.contractSent,
    ListingWorkflowStage.contractReturned,
    ListingWorkflowStage.contractSigned,
  };

  static const _marketerPermitStages = {
    ListingWorkflowStage.permitPending,
    ListingWorkflowStage.permitIssued,
  };

  // --- Owner tabs ---
  /// تبويبات العرض في «صفحتي» للمالك (0..6) — يطابق [TabBar] بعد «العروض المقدمة».
  /// 0 بانتظار المسوقين، 1 العروض المقدمة، 2 التعاقد، 3 توقف 72س، 4 ملغى، 5 محجوز، 6 صفقات مكتملة.
  static int ownerHubDisplayTabIndex(
    ListingWorkflowStage stage, {
    String? legacyListingStatus,
    int ownerPendingOffersCount = 0,
  }) {
    final st = (legacyListingStatus ?? '').trim().toLowerCase();
    if (stage == ListingWorkflowStage.archived) {
      if (st == 'sold' || st == 'completed') return 6;
      return 4;
    }
    if (ownerTabMatches(4, stage)) return 5;
    if (ownerTabMatches(3, stage)) return 4;
    if (ownerTabMatches(2, stage)) return 3;
    if (ownerTabMatches(1, stage)) return 2;
    if (ownerTabMatches(0, stage) || stage == ListingWorkflowStage.addedByOwner) {
      final offersHint = ownerPendingOffersCount > 0 ||
          const {'offers_received', 'assigned'}.contains(st);
      if (offersHint) return 1;
      return 0;
    }
    return 0;
  }

  static bool ownerTabMatches(int tabIndex, ListingWorkflowStage stage) {
    switch (tabIndex) {
      case 0:
        return stage == ListingWorkflowStage.waitingMarketers ||
            stage == ListingWorkflowStage.addedByOwner;
      case 1:
        return _ownerPostApprovalStages.contains(stage);
      case 2:
        return stage == ListingWorkflowStage.inactive72h;
      case 3:
        return stage == ListingWorkflowStage.cancelled ||
            stage == ListingWorkflowStage.contractCancelled ||
            stage == ListingWorkflowStage.terminated;
      case 4:
        return stage == ListingWorkflowStage.reserved;
      case 5:
        return stage == ListingWorkflowStage.published;
      default:
        return false;
    }
  }

  /// Marketer «صفحتي» — uses [publishedByMe] and [involved] flags from merged row.
  static bool marketerTabMatches(
    int tabIndex,
    ListingWorkflowStage stage, {
    required bool publishedByMe,
    required bool involvedInContract,
    required bool hasInviteOrOffer,
  }) {
    switch (tabIndex) {
      case 0:
        return hasInviteOrOffer &&
            (stage == ListingWorkflowStage.waitingMarketers ||
                stage == ListingWorkflowStage.addedByOwner);
      case 1:
        return hasInviteOrOffer &&
            stage == ListingWorkflowStage.waitingMarketers;
      case 2:
        return involvedInContract &&
            _marketerContractingStages.contains(stage);
      case 3:
        return involvedInContract && _marketerPermitStages.contains(stage);
      case 4:
        return publishedByMe &&
            (stage == ListingWorkflowStage.published ||
                stage == ListingWorkflowStage.reserved);
      case 5:
        return involvedInContract && stage == ListingWorkflowStage.inactive72h;
      case 6:
        return involvedInContract &&
            (stage == ListingWorkflowStage.cancelled ||
                stage == ListingWorkflowStage.contractCancelled ||
                stage == ListingWorkflowStage.terminated);
      default:
        return false;
    }
  }

  static String stageLabelEn(ListingWorkflowStage stage) {
    switch (stage) {
      case ListingWorkflowStage.addedByOwner:
        return 'Received';
      case ListingWorkflowStage.waitingMarketers:
        return 'Awaiting marketer offers';
      case ListingWorkflowStage.marketerSelected:
        return 'Owner approved';
      case ListingWorkflowStage.contractSent:
        return 'Contracting';
      case ListingWorkflowStage.contractPending:
      case ListingWorkflowStage.contractReturned:
      case ListingWorkflowStage.contractSigned:
        return 'Contracting';
      case ListingWorkflowStage.permitPending:
        return 'Permit (72h)';
      case ListingWorkflowStage.permitIssued:
        return 'Permit issued';
      case ListingWorkflowStage.published:
        return 'Published';
      case ListingWorkflowStage.reserved:
        return 'Reserved (72h)';
      case ListingWorkflowStage.inactive72h:
        return 'Inactive (72h)';
      case ListingWorkflowStage.contractCancelled:
        return 'Contract cancelled';
      case ListingWorkflowStage.cancelled:
      case ListingWorkflowStage.terminated:
        return 'Cancelled / terminated';
      case ListingWorkflowStage.archived:
        return 'Archived';
    }
  }

  static String stageLabelAr(ListingWorkflowStage stage) {
    switch (stage) {
      case ListingWorkflowStage.addedByOwner:
        return 'تم الاستلام';
      case ListingWorkflowStage.waitingMarketers:
        return 'بانتظار عروض المسوقين';
      case ListingWorkflowStage.marketerSelected:
        return 'تمت الموافقة';
      case ListingWorkflowStage.contractSent:
      case ListingWorkflowStage.contractPending:
      case ListingWorkflowStage.contractReturned:
      case ListingWorkflowStage.contractSigned:
        return 'بانتظار التصريح';
      case ListingWorkflowStage.permitPending:
        return 'إصدار التصاريح — 72 ساعة';
      case ListingWorkflowStage.permitIssued:
        return 'تم إصدار التصريح';
      case ListingWorkflowStage.published:
        return 'منشور';
      case ListingWorkflowStage.reserved:
        return 'محجوز مؤقتًا';
      case ListingWorkflowStage.inactive72h:
        return 'عقارات لم يتخذ عليها إجراء خلال 72 ساعة';
      case ListingWorkflowStage.contractCancelled:
        return 'عقد ملغى';
      case ListingWorkflowStage.cancelled:
      case ListingWorkflowStage.terminated:
        return 'العقود المفسوخة / الملغاة';
      case ListingWorkflowStage.archived:
        return 'مؤرشف';
    }
  }

  static Color stageColor(ListingWorkflowStage stage, ColorScheme cs) {
    switch (stage) {
      case ListingWorkflowStage.published:
        return Colors.green.shade700;
      case ListingWorkflowStage.reserved:
        return Colors.deepPurple.shade600;
      case ListingWorkflowStage.inactive72h:
        return Colors.blueGrey.shade500;
      case ListingWorkflowStage.contractCancelled:
      case ListingWorkflowStage.cancelled:
      case ListingWorkflowStage.terminated:
        return cs.error;
      case ListingWorkflowStage.permitPending:
      case ListingWorkflowStage.permitIssued:
      case ListingWorkflowStage.contractPending:
      case ListingWorkflowStage.contractSent:
      case ListingWorkflowStage.contractReturned:
      case ListingWorkflowStage.contractSigned:
        return Colors.blue.shade700;
      case ListingWorkflowStage.waitingMarketers:
      case ListingWorkflowStage.marketerSelected:
        return Colors.orange.shade800;
      default:
        return cs.primary;
    }
  }

  /// 0..7 for simplified progress strip
  static int progressIndex(ListingWorkflowStage stage) {
    switch (stage) {
      case ListingWorkflowStage.addedByOwner:
        return 0;
      case ListingWorkflowStage.waitingMarketers:
        return 1;
      case ListingWorkflowStage.marketerSelected:
      case ListingWorkflowStage.contractPending:
      case ListingWorkflowStage.contractSent:
      case ListingWorkflowStage.contractReturned:
      case ListingWorkflowStage.contractSigned:
        return 2;
      case ListingWorkflowStage.permitPending:
        return 3;
      case ListingWorkflowStage.permitIssued:
        return 3;
      case ListingWorkflowStage.published:
        return 4;
      case ListingWorkflowStage.reserved:
        return 5;
      case ListingWorkflowStage.inactive72h:
        return 6;
      case ListingWorkflowStage.contractCancelled:
      case ListingWorkflowStage.cancelled:
      case ListingWorkflowStage.terminated:
      case ListingWorkflowStage.archived:
        return 7;
    }
  }

  static String? deadlineLabelAr(DateTime? deadline) {
    if (deadline == null) return null;
    final left = deadline.difference(DateTime.now());
    if (left.isNegative) return 'انتهت المهلة';
    final h = left.inHours;
    final m = left.inMinutes.remainder(60);
    if (h > 0) return 'متبقي $hس $mد';
    return 'متبقي $mد';
  }
}
