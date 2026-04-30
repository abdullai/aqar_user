import 'package:flutter/material.dart';

import 'listing_workflow_stage.dart';

/// Owner hub tabs (صفحتي) — واجهة 7 تبويبات (0..6):
/// 0 بانتظار المسوقين، 1 تعاقد، 2 توقف 72س، 3 ملغى، 4 محجوز، 5 منشور، 6 صفقات مكتملة.
/// [ownerTabMatches] ما زال يستخدم فهارس منطقية قديمة (0,1,2,3,4,5,6) للفلترة؛ 7 لصفقات مكتملة في الفلتر فقط.
/// Marketer hub tabs (إدارتي) — indices 0..5
class ListingStageUiHelper {
  ListingStageUiHelper._();

  // --- Owner tabs ---
  /// تبويبات العرض في «صفحتي» (0..6) — يطابق ترتيب [TabBar].
  static int ownerHubDisplayTabIndex(
    ListingWorkflowStage stage, {
    String? legacyListingStatus,
  }) {
    final st = (legacyListingStatus ?? '').trim().toLowerCase();
    if (stage == ListingWorkflowStage.archived) {
      if (st == 'sold' || st == 'completed') return 6;
      return 3;
    }
    if (ownerTabMatches(5, stage)) return 4;
    if (ownerTabMatches(6, stage)) return 5;
    if (ownerTabMatches(3, stage)) return 2;
    if (ownerTabMatches(4, stage)) return 3;
    if (ownerTabMatches(1, stage)) return 1;
    if (ownerTabMatches(0, stage)) return 0;
    if (ownerTabMatches(2, stage)) return 5;
    return 0;
  }

  static bool ownerTabMatches(int tabIndex, ListingWorkflowStage stage) {
    switch (tabIndex) {
      case 0:
        return stage == ListingWorkflowStage.waitingMarketers ||
            stage == ListingWorkflowStage.addedByOwner;
      case 1:
        return stage == ListingWorkflowStage.marketerSelected ||
            stage == ListingWorkflowStage.contractPending ||
            stage == ListingWorkflowStage.contractSent ||
            stage == ListingWorkflowStage.contractReturned ||
            stage == ListingWorkflowStage.contractSigned ||
            stage == ListingWorkflowStage.permitPending ||
            stage == ListingWorkflowStage.permitIssued;
      case 2:
        return stage == ListingWorkflowStage.published ||
            stage == ListingWorkflowStage.reserved;
      case 3:
        return stage == ListingWorkflowStage.inactive72h;
      case 4:
        return stage == ListingWorkflowStage.cancelled ||
            stage == ListingWorkflowStage.contractCancelled ||
            stage == ListingWorkflowStage.terminated;
      case 5:
        return stage == ListingWorkflowStage.reserved;
      case 6:
        return stage == ListingWorkflowStage.published;
      default:
        return false;
    }
  }

  /// Marketer "إدارتي" — uses [publishedByMe] and [involved] flags from merged row.
  static bool marketerTabMatches(
    int tabIndex,
    ListingWorkflowStage stage, {
    required bool publishedByMe,
    required bool involvedInContract,
    required bool hasInviteOrOffer,
  }) {
    switch (tabIndex) {
      case 0:
        // دعوات ما زالت ضمن «استقبال المسوّقين» أو الطلب حديث بدون عروض بعد
        return hasInviteOrOffer &&
            (stage == ListingWorkflowStage.waitingMarketers ||
                stage == ListingWorkflowStage.addedByOwner);
      case 1:
        return involvedInContract &&
            const {
              ListingWorkflowStage.marketerSelected,
              ListingWorkflowStage.contractPending,
              ListingWorkflowStage.contractSent,
              ListingWorkflowStage.contractReturned,
              ListingWorkflowStage.contractSigned,
            }.contains(stage);
      case 2:
        return involvedInContract &&
            (stage == ListingWorkflowStage.permitPending ||
                stage == ListingWorkflowStage.permitIssued);
      case 3:
        return publishedByMe &&
            (stage == ListingWorkflowStage.published ||
                stage == ListingWorkflowStage.reserved);
      case 4:
        return involvedInContract && stage == ListingWorkflowStage.inactive72h;
      case 5:
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
        return 'Marketer selected';
      case ListingWorkflowStage.contractSent:
        return 'Awaiting contract';
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
        return 'تم اختيار المسوق';
      case ListingWorkflowStage.contractSent:
        return 'بانتظار العقد';
      case ListingWorkflowStage.contractPending:
      case ListingWorkflowStage.contractReturned:
      case ListingWorkflowStage.contractSigned:
        return 'التعاقد';
      case ListingWorkflowStage.permitPending:
        return 'بانتظار التصريح 72 ساعة';
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

  /// 0..8 for simplified progress strip
  static int progressIndex(ListingWorkflowStage stage) {
    switch (stage) {
      case ListingWorkflowStage.addedByOwner:
        return 0;
      case ListingWorkflowStage.waitingMarketers:
        return 1;
      case ListingWorkflowStage.marketerSelected:
        return 2;
      case ListingWorkflowStage.contractPending:
      case ListingWorkflowStage.contractSent:
      case ListingWorkflowStage.contractReturned:
      case ListingWorkflowStage.contractSigned:
        return 3;
      case ListingWorkflowStage.permitPending:
        return 4;
      case ListingWorkflowStage.permitIssued:
        return 4;
      case ListingWorkflowStage.published:
        return 5;
      case ListingWorkflowStage.reserved:
        return 6;
      case ListingWorkflowStage.inactive72h:
        return 7;
      case ListingWorkflowStage.contractCancelled:
      case ListingWorkflowStage.cancelled:
      case ListingWorkflowStage.terminated:
      case ListingWorkflowStage.archived:
        return 8;
    }
  }

  static String? deadlineLabelAr(DateTime? deadline) {
    if (deadline == null) return null;
    final left = deadline.difference(DateTime.now());
    if (left.isNegative) return 'انتهت المهلة';
    final h = left.inHours;
    final m = left.inMinutes.remainder(60);
    if (h > 0) return 'متبقي ${h}س ${m}د';
    return 'متبقي ${m}د';
  }
}
