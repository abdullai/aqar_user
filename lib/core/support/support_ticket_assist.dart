/// تصنيف ومسودة رد محلية — ليست نموذجاً لغوياً ولا تنفّذ دفعاً أو حظراً.
abstract final class SupportTicketAssist {
  SupportTicketAssist._();

  static String classify({
    required String subject,
    required String body,
    required String kind,
  }) {
    final t = '${subject.toLowerCase()} ${body.toLowerCase()} $kind';
    if (t.contains('دفع') ||
        t.contains('فاتور') ||
        t.contains('pay') ||
        t.contains('moyasar') ||
        t.contains('اشتراك')) {
      return 'billing';
    }
    if (t.contains('حظر') || t.contains('ban') || t.contains('إساءة')) {
      return 'moderation';
    }
    if (kind == 'suggestion' || t.contains('اقتراح') || t.contains('suggest')) {
      return 'suggestion';
    }
    return 'general';
  }

  static String draftAck({
    required bool isAr,
    required String category,
    required String kind,
  }) {
    if (category == 'billing') {
      return isAr
          ? 'مسودة: تم استلام موضوع الفوترة. القرار المالي يتم حصراً عبر الخادم وسجل التدقيق — لن يُنفَّذ دفع أو تفعيل من هذه الرسالة.'
          : 'Draft: billing topic received. Financial decisions run only via server RPC and audit — this message does not charge or activate anything.';
    }
    if (category == 'moderation') {
      return isAr
          ? 'مسودة: بلاغ/حظر يحتاج مراجعة موظف عبر RPC. لن يُحظر حساب من نموذج لغوي.'
          : 'Draft: moderation needs a staff RPC review. No account is banned by a language model.';
    }
    if (kind == 'suggestion') {
      return isAr
          ? 'تم استلام اقتراحك — سيراجعه الدعم داخل التطبيق.'
          : 'Your suggestion was received — support will review it in-app.';
    }
    return isAr
        ? 'تم استلام شكواك — سيتواصل معك فريق الدعم داخل التطبيق.'
        : 'Your complaint was received — support will follow up in-app.';
  }

  /// مسودة رد للموظف فقط — لا تنفّذ دفعاً أو حظراً.
  static String draftStaffReply({
    required bool isAr,
    required String subject,
    required String body,
    required String kind,
  }) {
    final category = classify(subject: subject, body: body, kind: kind);
    if (category == 'billing') {
      return isAr
          ? 'مسودة للموظف: استلمنا موضوع الفوترة. أي خصم أو تفعيل يتم حصراً عبر دوال الخادم وسجل التدقيق — هذه الرسالة لا تنفّذ دفعاً.'
          : 'Staff draft: billing topic noted. Any charge or activation runs only via server RPC and audit — this message does not execute payment.';
    }
    if (category == 'moderation') {
      return isAr
          ? 'مسودة للموظف: البلاغ يحتاج مراجعة امتثال عبر RPC. لن يُحظر حساب من هذه المسودة.'
          : 'Staff draft: this report needs a compliance RPC review. This draft does not ban anyone.';
    }
    return isAr
        ? 'مسودة للموظف: شكراً لتواصلك. راجعنا التذكرة وسنتابع من داخل التطبيق.'
        : 'Staff draft: thank you for writing. We reviewed the ticket and will follow up in-app.';
  }
}
