/// رسائل ودّية بدل استثناءات Postgres الخام في واجهة المستخدم.
abstract final class RpcUserMessage {
  static String of(Object error, {required bool isAr}) {
    final raw = error.toString();
    final s = raw.toLowerCase();

    if (s.contains('property_not_reserved')) {
      return isAr
          ? 'الحجز قائم لكن حالة الإعلان لم تُحدَّث. أعد المحاولة بعد تطبيق إصلاح قاعدة البيانات، أو حدّث الصفحة.'
          : 'The hold exists but the listing stage was out of sync. Retry after applying the database fix, or refresh.';
    }
    if (s.contains('not assigned yet') ||
        s.contains('55000') ||
        s.contains('tuple structure')) {
      return isAr
          ? 'تعذّر إلغاء الصفقة بسبب خطأ في الخادم. طبّق سكربت الإصلاح ثم أعد المحاولة.'
          : 'Cancel failed due to a server bug. Apply the database fix, then try again.';
    }
    if (s.contains('no_active_reservation')) {
      return isAr
          ? 'لا يوجد حجز نشط لهذا الإعلان.'
          : 'There is no active hold on this listing.';
    }
    if (s.contains('deal_applicants_cap')) {
      return isAr
          ? 'اكتمل الحد: 10 طلبات إتمام على هذه البطاقة. انتظر حتى يسحب أحدهم عرضه.'
          : 'This card already has 10 complete-deal requests. Wait until someone withdraws.';
    }
    if (s.contains('deal_slot_limit')) {
      return isAr
          ? 'صفقاتي ممتلئة. أتمّ أو ألغِ أو احذف صفقة قبل إضافة أخرى.'
          : 'My deals is full. Complete, cancel, or remove a deal before adding another.';
    }
    if (s.contains('inventory_slot_limit')) {
      return isAr
          ? 'طلباتي/إعلاناتي ممتلئة. أتمّ أو ألغِ أو احذف بطاقات قبل إضافة المزيد.'
          : 'Listings and requests are full. Complete, cancel, or delete cards before adding more.';
    }
    if (s.contains('not_reservation_owner') || s.contains('not_authorized')) {
      return isAr
          ? 'ليست لديك صلاحية تنفيذ هذا الإجراء.'
          : 'You are not allowed to perform this action.';
    }
    if (s.contains('reservation_not_found')) {
      return isAr ? 'لم يُعثر على الصفقة.' : 'Deal was not found.';
    }
    if (s.contains('staff_reply_required')) {
      return isAr
          ? 'يظهر «تم الحل» و«لم يتم الحل» بعد رد الإدارة فقط.'
          : '“Resolved” and “Not resolved” are available only after administration replies.';
    }
    if (s.contains('sla_not_elapsed')) {
      return isAr
          ? 'التصعيد يُتاح بعد مرور 24 ساعة على رفع التذكرة إذا لم تُحل.'
          : 'Escalation is available 24 hours after submission if the ticket is still unresolved.';
    }
    if (s.contains('already_escalated')) {
      return isAr ? 'هذه التذكرة مُصعَّدة مسبقاً.' : 'This ticket is already escalated.';
    }
    if (s.contains('photo_limit_exceeded')) {
      return isAr
          ? 'تجاوزت حد عدد الصور المتفق عليه لهذا الطلب.'
          : 'You exceeded the agreed photo count for this request.';
    }
    if (s.contains('video_not_allowed')) {
      return isAr
          ? 'هذا الطلب لا يشمل فيديو.'
          : 'This request does not include video.';
    }
    if (s.contains('tour_not_requested')) {
      return isAr
          ? 'هذا الطلب لا يشمل جولة داخلية.'
          : 'This request does not include an in-app tour.';
    }
    if (s.contains('shoot_accept_expired')) {
      return isAr
          ? 'انتهت مهلة 24 ساعة لقبول هذا الطلب وأُلغي تلقائياً.'
          : 'The 24-hour window to accept this request ended and it was cancelled.';
    }
    if (s.contains('daily_accept_cap')) {
      return isAr
          ? 'وصلت حد قبول طلبات التصوير لهذا اليوم. يمكنك رفعه من إعدادات المصور.'
          : 'You reached today’s photo-shoot accept limit. Raise it from photographer settings.';
    }
    if (s.contains('policy_not_accepted')) {
      return isAr
          ? 'وافق على سياسة الخدمة والأسعار للمتابعة.'
          : 'Accept the service and pricing policy to continue.';
    }
    if (s.contains('identity_required')) {
      return isAr
          ? 'أدخل رقم الهوية أو السجل التجاري.'
          : 'Enter a national ID or commercial registration number.';
    }
    if (s.contains('photographer_not_verified')) {
      return isAr
          ? 'هذا المصور غير موثّق بعد.'
          : 'This photographer is not verified yet.';
    }
    if (s.contains('reject_reason_required')) {
      return isAr ? 'سبب الرفض مطلوب.' : 'A decline reason is required.';
    }
    if (s.contains('cannot_book_self')) {
      return isAr
          ? 'لا يمكنك طلب تصوير من حسابك.'
          : 'You cannot book a shoot with your own account.';
    }
    if (s.contains('offers_marketer_fk') ||
        s.contains('marketer_profile_required') ||
        s.contains('not_a_marketer') ||
        (s.contains('marketer_profiles') &&
            (s.contains('23503') || s.contains('foreign key')))) {
      return isAr
          ? 'حسابك التسويقي غير مكتمل. حدّث الصفحة ثم أعد المحاولة.'
          : 'Your marketing profile is incomplete. Refresh and try again.';
    }
    if (s.contains('offers_cap_reached')) {
      return isAr
          ? 'اكتمل الحد الأعلى: 6 عروض على هذا الطلب.'
          : 'This listing already has 6 offers.';
    }
    if (s.contains('owner_cannot_offer')) {
      return isAr
          ? 'لا يمكنك تقديم عرض على طلبك.'
          : 'You cannot offer on your own listing request.';
    }
    if (s.contains('previous_marketer_blocked')) {
      return isAr
          ? 'انتهت فرصتك على هذا الطلب إلا بعد «إتاحة فرصة».'
          : 'Your turn ended unless you grant another chance.';
    }
    if (raw.contains('PostgrestException') || raw.contains('PostgresException')) {
      final m = RegExp(r'message:\s*([^,\n]+)').firstMatch(raw);
      final msg = (m?.group(1) ?? '').trim();
      if (msg.isNotEmpty && msg.length < 120 && !msg.contains('record')) {
        return msg;
      }
    }
    return isAr
        ? 'تعذّر إكمال العملية. حدّث الصفحة ثم أعد المحاولة.'
        : 'Could not complete the action. Refresh and try again.';
  }
}
