import '../../services/support_ticket_service.dart';

/// قواعد واضحة للمستخدم والإدارة: رد ≠ تصعيد، و«لم يتم الحل» بعد رد الإدارة فقط.
abstract final class SupportTicketPolicy {
  SupportTicketPolicy._();

  /// مهلة أول رد / أحقية التصعيد من وقت رفع التذكرة.
  static const Duration escalateAfter = Duration(hours: 24);

  static bool isResolved(SupportTicketRow t) {
    final st = t.status.trim().toLowerCase();
    if (st == 'resolved' || st == 'closed') return true;
    return t.userResolution.trim().toLowerCase() == 'resolved';
  }

  static bool isEscalated(SupportTicketRow t) {
    if (t.status.trim().toLowerCase() == 'escalated') return true;
    return t.userResolution.trim().toLowerCase() == 'escalated';
  }

  static bool isInternalDraftText(String text) {
    final t = text.trim();
    if (t.isEmpty) return true;
    if (t.startsWith('مسودة للموظف') || t.startsWith('مسودة:')) return true;
    final l = t.toLowerCase();
    return l.startsWith('staff draft') || l.startsWith('draft:');
  }

  static bool isWelcomeText(String text) {
    final t = text.trim();
    if (t.contains('من دعم المنصة') && t.contains('كيف نقدر نخدمك')) {
      return true;
    }
    final l = t.toLowerCase();
    return l.contains('from platform support') &&
        l.contains('how can we help');
  }

  static bool isPublicStaffMessage(Map<String, dynamic> m) {
    final role = '${m['role'] ?? ''}'.trim().toLowerCase();
    if (role != 'staff') return false;
    final text = '${m['text'] ?? ''}'.trim();
    if (text.isEmpty || isInternalDraftText(text) || isWelcomeText(text)) {
      return false;
    }
    final kind = '${m['kind'] ?? ''}'.trim().toLowerCase();
    if (kind == 'welcome' || m['welcome'] == true) return false;
    return true;
  }

  /// رد موظف حقيقي — الترحيب الآلي ومسودة الموظف لا يُحسبان رداً.
  static bool hasStaffReply(SupportTicketRow t) {
    final reply = (t.adminReply ?? '').trim();
    if (reply.isNotEmpty &&
        !isInternalDraftText(reply) &&
        !isWelcomeText(reply)) {
      return true;
    }
    return t.chatThread.any(isPublicStaffMessage);
  }

  static DateTime? escalateAvailableAt(SupportTicketRow t) {
    final created = t.createdAt;
    if (created == null) return null;
    return created.toLocal().add(escalateAfter);
  }

  static bool slaElapsed(SupportTicketRow t, {DateTime? now}) {
    final at = escalateAvailableAt(t);
    if (at == null) return false;
    return (now ?? DateTime.now()).isAfter(at) ||
        (now ?? DateTime.now()).isAtSameMomentAs(at);
  }

  static Duration? slaRemaining(SupportTicketRow t, {DateTime? now}) {
    final at = escalateAvailableAt(t);
    if (at == null) return null;
    final left = at.difference(now ?? DateTime.now());
    if (left.isNegative) return Duration.zero;
    return left;
  }

  static bool canMarkResolved(SupportTicketRow t) =>
      hasStaffReply(t) && !isResolved(t);

  static bool canMarkUnresolved(SupportTicketRow t) =>
      hasStaffReply(t) && !isResolved(t);

  static bool canEscalate(SupportTicketRow t, {DateTime? now}) {
    if (isResolved(t) || isEscalated(t)) return false;
    return slaElapsed(t, now: now);
  }
}
