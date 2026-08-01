import 'package:intl/intl.dart';

/// نصوص واجهة فقط: تحويل قيم قاعدة البيانات إلى عبارات مفهومة (بدون عرض مفاتيح خام).
class WorkflowDisplayTexts {
  WorkflowDisplayTexts._();

  /// اسم مستعار لـ [workflowStage] (واجهات جديدة).
  static String stage(String? stageCode, bool isAr) =>
      workflowStage(stageCode, isAr);

  /// تنسيق تاريخ/وقت للواجهة (مثال: ١٠ مايو ٢٠٢٦ – ٣:٤٥ م).
  static String formatDateTime(DateTime dt, bool isAr) {
    final loc = isAr ? 'ar' : 'en';
    try {
      if (isAr) {
        return DateFormat('d MMMM yyyy – h:mm a', loc).format(dt.toLocal());
      }
      return DateFormat('MMMM d, yyyy – h:mm a', loc).format(dt.toLocal());
    } catch (_) {
      return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
    }
  }

  static String workflowStage(String? stage, bool isAr) {
    final s = (stage ?? '').trim().toLowerCase();
    if (isAr) {
      switch (s) {
        case 'added_by_owner':
          return 'تم إنشاء الطلب';
        case 'waiting_marketers':
          return 'بانتظار عروض المسوقين';
        case 'marketer_selected':
          return 'تم اختيار المسوق';
        case 'contract_pending':
          return 'بانتظار العقد';
        case 'contract_sent':
          return 'تم إرسال العقد للمالك';
        case 'contract_returned':
          return 'أعيد العقد للتعديل';
        case 'contract_signed':
          return 'تم توقيع العقد';
        case 'contract_cancelled':
          return 'عقد ملغى';
        case 'permit_pending':
          return 'إصدار التصاريح — مهلة ٧٢ ساعة';
        case 'permit_issued':
          return 'تم إصدار التصريح';
        case 'published':
          return 'منشور';
        case 'reserved':
          return 'محجوز مؤقتاً';
        case 'inactive_72h':
        case 'inactive72h':
          return 'لم يُتخذ إجراء خلال مهلة ٧٢ ساعة';
        case 'cancelled':
          return 'ملغى';
        case 'terminated':
          return 'منتهٍ';
        case 'archived':
          return 'مؤرشف';
        default:
          return s.isEmpty ? '—' : 'قيد المعالجة';
      }
    }
    switch (s) {
      case 'added_by_owner':
        return 'Request created';
      case 'waiting_marketers':
        return 'Awaiting marketer offers';
      case 'marketer_selected':
        return 'Marketer selected';
      case 'contract_pending':
        return 'Contract pending';
      case 'contract_sent':
        return 'Contract sent to owner';
      case 'contract_returned':
        return 'Contract returned for edits';
      case 'contract_signed':
        return 'Contract signed';
      case 'contract_cancelled':
        return 'Contract cancelled';
      case 'permit_pending':
        return 'Permit issuance — 72h window';
      case 'permit_issued':
        return 'Permit issued';
      case 'published':
        return 'Published';
      case 'reserved':
        return 'Temporarily reserved';
      case 'inactive_72h':
      case 'inactive72h':
        return 'No action within 72h window';
      case 'cancelled':
        return 'Cancelled';
      case 'terminated':
        return 'Terminated';
      case 'archived':
        return 'Archived';
      default:
        return s.isEmpty ? '—' : 'In progress';
    }
  }

  static String requestStatus(String? status, bool isAr) {
    final s = (status ?? '').trim().toLowerCase();
    if (isAr) {
      switch (s) {
        case 'offers_received':
          return 'وصلت عروض';
        case 'waiting_marketers':
          return 'بانتظار المسوقين';
        case 'active':
        case 'live':
        case 'published':
          return 'نشط';
        case 'inactive_72h':
        case 'inactive72h':
          return 'متوقف — لم يُتخذ إجراء';
        case 'cancelled':
        case 'terminated':
          return 'غير نشط';
        default:
          return s.isEmpty ? '—' : 'قيد المعالجة';
      }
    }
    switch (s) {
      case 'offers_received':
        return 'Offers received';
      case 'waiting_marketers':
        return 'Waiting for marketers';
      case 'active':
      case 'live':
      case 'published':
        return 'Active';
      case 'inactive_72h':
      case 'inactive72h':
        return 'Paused — no action';
      case 'cancelled':
      case 'terminated':
        return 'Inactive';
      default:
        return s.isEmpty ? '—' : 'In progress';
    }
  }

  static String offerStatus(String? status, bool isAr) {
    final s = (status ?? '').trim().toLowerCase();
    if (isAr) {
      switch (s) {
        case '':
        case 'submitted':
        case 'pending':
          return 'قيد الانتظار (بانتظار رد المالك)';
        case 'owner_accepted':
        case 'selected':
          return 'مقبول من المالك';
        case 'owner_rejected':
        case 'rejected':
          return 'مرفوض من المالك';
        case 'declined':
          return 'مرفوض';
        case 'withdrawn':
          return 'مسحوب من المسوّق';
        case 'expired':
          return 'منتهي المهلة';
        case 'converted_to_contract':
          return 'حُوّل إلى عقد';
        case 'cancelled':
          return 'ملغى';
        default:
          return s.isEmpty ? '—' : 'قيد المعالجة';
      }
    }
    switch (s) {
      case '':
      case 'submitted':
      case 'pending':
        return 'Pending (awaiting owner)';
      case 'owner_accepted':
      case 'selected':
        return 'Accepted by owner';
      case 'owner_rejected':
      case 'rejected':
        return 'Rejected by owner';
      case 'declined':
        return 'Declined';
      case 'withdrawn':
        return 'Withdrawn by marketer';
      case 'expired':
        return 'Expired';
      case 'converted_to_contract':
        return 'Converted to contract';
      case 'cancelled':
        return 'Cancelled';
      default:
        return s.isEmpty ? '—' : 'In progress';
    }
  }

  static String inviteStatus(String? status, bool isAr) {
    final s = (status ?? '').trim().toLowerCase();
    if (isAr) {
      switch (s) {
        case 'pending':
          return 'قيد الانتظار';
        case 'invited':
          return 'مُرسلة للمسوّق';
        case 'seen':
          return 'اطّلع المسوّق';
        case 'declined':
          return 'مرفوضة من المسوّق';
        case 'expired':
          return 'منتهية';
        case 'offered':
          return 'قُدِّم عرض';
        case 'accepted':
          return 'مقبولة';
        case 'withdrawn':
          return 'مسحوبة';
        default:
          return s.isEmpty ? '—' : 'قيد المعالجة';
      }
    }
    switch (s) {
      case 'pending':
        return 'Pending';
      case 'invited':
        return 'Sent to marketer';
      case 'seen':
        return 'Seen by marketer';
      case 'declined':
        return 'Declined by marketer';
      case 'expired':
        return 'Expired';
      case 'offered':
        return 'Offer submitted';
      case 'accepted':
        return 'Accepted';
      case 'withdrawn':
        return 'Withdrawn';
      default:
        return s.isEmpty ? '—' : 'In progress';
    }
  }

  static String contractStatus(String? status, bool isAr) {
    final s = (status ?? '').trim().toLowerCase();
    if (isAr) {
      switch (s) {
        case 'draft':
          return 'مسودة';
        case 'pending_marketer':
          return 'بانتظار المسوّق';
        case 'pending_owner':
          return 'بانتظار المالك';
        case 'sent':
        case 'awaiting_owner':
          return 'أُرسل للمالك';
        case 'signed':
          return 'موقّع';
        case 'returned':
          return 'عاد للتعديل';
        case 'cancelled':
          return 'ملغى';
        default:
          return s.isEmpty ? '—' : 'قيد المعالجة';
      }
    }
    switch (s) {
      case 'draft':
        return 'Draft';
      case 'pending_marketer':
        return 'Awaiting marketer';
      case 'pending_owner':
        return 'Awaiting owner';
      case 'sent':
      case 'awaiting_owner':
        return 'Sent to owner';
      case 'signed':
        return 'Signed';
      case 'returned':
        return 'Returned for edits';
      case 'cancelled':
        return 'Cancelled';
      default:
        return s.isEmpty ? '—' : 'In progress';
    }
  }

  static String accountType(String? type, bool isAr) {
    final s = (type ?? '').trim().toLowerCase();
    if (isAr) {
      switch (s) {
        case 'office':
        case 'brokerage_office':
          return 'مكتب عقاري';
        case 'company':
          return 'شركة عقارية';
        case 'establishment':
        case 'institution':
          return 'مؤسسة عقارية';
        case 'marketer':
          return 'مسوق عقاري';
        default:
          return s.isEmpty ? '—' : 'حساب مسوّق';
      }
    }
    switch (s) {
      case 'office':
      case 'brokerage_office':
        return 'Real estate office';
      case 'company':
        return 'Real estate company';
      case 'establishment':
      case 'institution':
        return 'Establishment';
      case 'marketer':
        return 'Marketer';
      default:
        return s.isEmpty ? '—' : 'Marketer account';
    }
  }
}
