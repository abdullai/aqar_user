import 'package:supabase_flutter/supabase_flutter.dart';

/// عمليات صندوق المحادثات: أرشفة، إخفاء، حذف، قراءة الكل، حظر.
class ChatInboxService {
  ChatInboxService(this.sb);

  final SupabaseClient sb;

  String? get _uid => sb.auth.currentUser?.id;

  Future<void> archiveConversation(String conversationId) async {
    final cid = conversationId.trim();
    if (cid.isEmpty) return;
    await sb.rpc('archive_conversation_for_me', params: {'p_cid': cid});
  }

  Future<void> hideConversation(String conversationId) async {
    final cid = conversationId.trim();
    if (cid.isEmpty) return;
    await sb.rpc('hide_conversation_for_me', params: {'p_cid': cid});
  }

  Future<void> deleteConversation(String conversationId) async {
    final cid = conversationId.trim();
    if (cid.isEmpty) return;
    await sb.rpc('delete_conversation_for_me', params: {'p_cid': cid});
  }

  Future<void> unarchiveConversation(String conversationId) async {
    final cid = conversationId.trim();
    if (cid.isEmpty) return;
    await sb.rpc('unarchive_conversation_for_me', params: {'p_cid': cid});
  }

  Future<int> markAllConversationsRead() async {
    try {
      final res = await sb.rpc('mark_all_conversations_read');
      if (res is int) return res;
      if (res is num) return res.toInt();
    } catch (_) {}
    return 0;
  }

  Future<void> blockUser(String userId) async {
    final id = userId.trim();
    if (id.isEmpty || id == _uid) return;
    await sb.rpc('block_chat_user', params: {'p_user_id': id});
  }

  Future<void> unblockUser(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    await sb.rpc('unblock_chat_user', params: {'p_user_id': id});
  }

  Future<bool> isUserBlocked(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return false;
    try {
      final res = await sb.rpc('is_chat_user_blocked', params: {'p_user_id': id});
      if (res is bool) return res;
      return res == true || res.toString().toLowerCase() == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> adminDeleteOrgChannelPost(String postId) async {
    final pid = postId.trim();
    if (pid.isEmpty) return;
    await sb.rpc('admin_delete_org_channel_post', params: {'p_post_id': pid});
  }

  Future<void> adminSuspendOrgChatMember({
    required String orgId,
    required String userId,
    int hours = 24,
    String? reason,
  }) async {
    await sb.rpc(
      'admin_suspend_org_chat_member',
      params: {
        'p_org_id': orgId.trim(),
        'p_user_id': userId.trim(),
        'p_hours': hours,
        'p_reason': reason,
      },
    );
  }

  Future<void> adminUnsuspendOrgChatMember({
    required String orgId,
    required String userId,
  }) async {
    await sb.rpc(
      'admin_unsuspend_org_chat_member',
      params: {
        'p_org_id': orgId.trim(),
        'p_user_id': userId.trim(),
      },
    );
  }
}

enum ChatInboxSort { recent, unreadFirst, nameAz }

List<T> sortChatInboxRows<T>({
  required List<T> rows,
  required ChatInboxSort sort,
  required String Function(T) conversationId,
  required int Function(T) unreadCount,
  required String Function(T) displayName,
  required DateTime? Function(T) lastMessageAt,
}) {
  final copy = List<T>.from(rows);
  switch (sort) {
    case ChatInboxSort.unreadFirst:
      copy.sort((a, b) {
        final ua = unreadCount(a);
        final ub = unreadCount(b);
        if (ua != ub) return ub.compareTo(ua);
        final ta = lastMessageAt(a);
        final tb = lastMessageAt(b);
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
    case ChatInboxSort.nameAz:
      copy.sort((a, b) {
        final na = displayName(a).toLowerCase();
        final nb = displayName(b).toLowerCase();
        final c = na.compareTo(nb);
        if (c != 0) return c;
        return conversationId(a).compareTo(conversationId(b));
      });
    case ChatInboxSort.recent:
      copy.sort((a, b) {
        final ta = lastMessageAt(a);
        final tb = lastMessageAt(b);
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
  }
  return copy;
}
