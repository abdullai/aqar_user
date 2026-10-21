import 'package:supabase_flutter/supabase_flutter.dart';

/// يشغّل تذكيرات المعاينة المستحقة للمستخدم (خلال 24 ساعة) مرة كل 30 دقيقة كحد أقصى.
/// الخادم يمنع التكرار؛ وعند توفر pg_cron تصل التذكيرات دون فتح التطبيق.
abstract final class ViewingReminderService {
  static DateTime? _last;

  static Future<void> runIfDue() async {
    final now = DateTime.now();
    if (_last != null && now.difference(_last!) < const Duration(minutes: 30)) {
      return;
    }
    _last = now;
    try {
      await Supabase.instance.client.rpc('send_due_viewing_reminders');
    } catch (_) {}
  }
}
