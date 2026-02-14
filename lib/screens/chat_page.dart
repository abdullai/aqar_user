// lib/screens/chat_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/session/app_session.dart';

enum ConversationKind { support, property }

// =========================
// Model
// =========================

class _ConversationInfo {
  final String id;
  final String counterpartyId;
  final String? title;

  const _ConversationInfo({
    required this.id,
    required this.counterpartyId,
    required this.title,
  });
}

class _ChatListRow {
  final String conversationId;
  final String kind;
  final String? title;
  final String? otherUserId;
  final String? otherFullName;
  final String? otherPhone;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  const _ChatListRow({
    required this.conversationId,
    required this.kind,
    required this.title,
    required this.otherUserId,
    required this.otherFullName,
    required this.otherPhone,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
  });

  static _ChatListRow fromMap(Map<String, dynamic> m) {
    DateTime? dt;
    final raw = m['last_message_at'];
    if (raw is String && raw.isNotEmpty) {
      dt = DateTime.tryParse(raw)?.toLocal();
    } else if (raw is DateTime) {
      dt = raw.toLocal();
    }

    int unread = 0;
    final ur = m['unread_count'];
    if (ur is int) unread = ur;
    if (ur is num) unread = ur.toInt();

    return _ChatListRow(
      conversationId: (m['conversation_id'] ?? '').toString(),
      kind: (m['kind'] ?? '').toString(),
      title: (m['title'] as String?)?.trim(),
      otherUserId: (m['other_user_id'] ?? '').toString().trim().isEmpty
          ? null
          : (m['other_user_id'] ?? '').toString().trim(),
      otherFullName: (m['other_full_name'] as String?)?.trim(),
      otherPhone: (m['other_phone'] as String?)?.trim(),
      lastMessage: (m['last_message'] as String?)?.trim(),
      lastMessageAt: dt,
      unreadCount: unread,
    );
  }
}

class ChatPage extends StatefulWidget {
  final bool isAr;

  /// إذا مررته سيفتح المحادثة مباشرة
  final String? conversationId;

  /// فتح محادثة عقار
  final String? propertyId;
  final String? reservationId;

  /// الطرف الآخر (المعلن/الدعم). في محادثة العقار إذا لم يمرر سيتم جلب owner_id من properties.
  final String? counterpartyId;

  /// عنوان اختياري للمحادثة
  final String? title;

  /// نوع المحادثة عند الفتح المباشر بدون conversationId
  final ConversationKind? kind;

  /// UUID لحساب الدعم (messages.receiver_id NOT NULL)
  final String? supportUserId;

  const ChatPage({
    super.key,
    this.isAr = true,
    this.conversationId,
    this.propertyId,
    this.reservationId,
    this.counterpartyId,
    this.title,
    this.kind,
    this.supportUserId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _sb = Supabase.instance.client;

  String get _uid => _sb.auth.currentUser?.id ?? '';
  bool get _isGuest => _uid.isEmpty;

  bool _booting = true;
  String? _bootError;

  String? _activeConversationId;
  ConversationKind? _activeKind;
  String? _activeTitle;

  /// الطرف الآخر الحقيقي (receiver_id)
  String? _activeCounterpartyId;

  final TextEditingController _tc = TextEditingController();
  bool _sending = false;

  bool _bootStarted = false;

  // list refresh key
  int _listReloadTick = 0;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  // =========================
  // Helpers
  // =========================

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
  }

  /// ✅ يحدد الطرف الآخر الصحيح اعتمادًا على user_id / counterparty_id
  String? _resolveOtherPartyId(Map<String, dynamic> conv) {
    final userId = (conv['user_id'] ?? '').toString().trim();
    final cpId = (conv['counterparty_id'] ?? '').toString().trim();

    if (_uid.isEmpty) return null;

    if (_uid == userId) return cpId.isEmpty ? null : cpId;
    if (_uid == cpId) return userId.isEmpty ? null : userId;

    // fallback
    if (cpId.isNotEmpty && cpId != _uid) return cpId;
    if (userId.isNotEmpty && userId != _uid) return userId;
    return null;
  }

  ConversationKind _parseKind(dynamic raw) {
    final k = (raw ?? '').toString();
    return k == 'support'
        ? ConversationKind.support
        : ConversationKind.property;
  }

  String _defaultTitleFor(ConversationKind kind) {
    if (kind == ConversationKind.support)
      return widget.isAr ? 'الدعم' : 'Support';
    return widget.isAr ? 'دردشة العقار' : 'Property chat';
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // =========================
  // Boot
  // =========================

  Future<void> _boot() async {
    if (_bootStarted) return;
    _bootStarted = true;

    if (_isGuest) {
      setState(() {
        _booting = false;
        _bootError = widget.isAr
            ? 'يجب تسجيل الدخول لعرض الدردشة'
            : 'You must log in to use chat';
      });
      return;
    }

    final session = context.read<AppSession>();

    // ✅ لا نبدأ أي شبكات بدون إنترنت
    final ok = await session.runNetworkGuarded<bool>(
      context: context,
      action: () async => true,
    );
    if (ok != true) {
      setState(() {
        _booting = false;
        _bootError =
            widget.isAr ? 'لا يوجد اتصال بالإنترنت' : 'No internet connection';
      });
      return;
    }

    try {
      // 1) فتح مباشر عبر conversationId
      final directCid = (widget.conversationId ?? '').trim();
      if (directCid.isNotEmpty) {
        final conv = await session.runNetworkGuarded<Map<String, dynamic>?>(
          context: context,
          action: () async {
            return await _sb
                .from('conversations')
                .select('id, kind, title, user_id, counterparty_id')
                .eq('id', directCid)
                .maybeSingle();
          },
        );

        if (conv == null) {
          throw Exception(
              widget.isAr ? 'المحادثة غير موجودة' : 'Conversation not found');
        }

        final otherPartyId = _resolveOtherPartyId(conv);
        if (otherPartyId == null || otherPartyId.trim().isEmpty) {
          throw Exception(widget.isAr
              ? 'تعذر تحديد الطرف الآخر'
              : 'Cannot resolve other party');
        }

        setState(() {
          _activeConversationId = (conv['id'] ?? '').toString();
          _activeKind = _parseKind(conv['kind']);
          _activeTitle = (conv['title'] as String?)?.trim();
          _activeCounterpartyId = otherPartyId;
          _booting = false;
        });

        // ✅ مثل واتساب: عند فتح المحادثة نعلّم الرسائل كمقروءة
        unawaited(_markReadSafe());
        return;
      }

      // 2) فتح محادثة عقار
      if (widget.kind == ConversationKind.property &&
          (widget.propertyId ?? '').trim().isNotEmpty) {
        final info = await _getOrCreatePropertyConversation(
          propertyId: widget.propertyId!.trim(),
          reservationId: (widget.reservationId ?? '').trim().isEmpty
              ? null
              : widget.reservationId!.trim(),
          ownerId: (widget.counterpartyId ?? '').trim().isEmpty
              ? null
              : widget.counterpartyId!.trim(),
          title: widget.title,
        );

        setState(() {
          _activeConversationId = info.id;
          _activeKind = ConversationKind.property;
          _activeTitle = (info.title ?? '').trim().isEmpty
              ? _defaultTitleFor(ConversationKind.property)
              : info.title!.trim();
          _activeCounterpartyId = info.counterpartyId;
          _booting = false;
        });

        unawaited(_markReadSafe());
        return;
      }

      // 3) فتح دعم
      if (widget.kind == ConversationKind.support) {
        final supportId = (widget.supportUserId ?? '').trim();
        if (supportId.isEmpty) {
          throw Exception(widget.isAr
              ? 'يجب تحديد supportUserId (UUID) لأن receiver_id في messages لا يقبل null'
              : 'supportUserId is required because messages.receiver_id is NOT NULL');
        }

        final info = await _getOrCreateSupportConversation(
          supportUserId: supportId,
          title: widget.title,
        );

        setState(() {
          _activeConversationId = info.id;
          _activeKind = ConversationKind.support;
          _activeTitle = (info.title ?? '').trim().isEmpty
              ? _defaultTitleFor(ConversationKind.support)
              : info.title!.trim();
          _activeCounterpartyId = info.counterpartyId; // = supportId
          _booting = false;
        });

        unawaited(_markReadSafe());
        return;
      }

      // 4) قائمة المحادثات
      setState(() {
        _activeConversationId = null;
        _activeKind = null;
        _activeTitle = null;
        _activeCounterpartyId = null;
        _booting = false;
      });
    } catch (e) {
      setState(() {
        _booting = false;
        _bootError = e.toString();
      });
    }
  }

  // =========================
  // WhatsApp-like: Mark Read
  // =========================

  Future<void> _markReadSafe() async {
    final cid = (_activeConversationId ?? '').trim();
    if (cid.isEmpty) return;

    final session = context.read<AppSession>();
    await session.runNetworkGuarded<int>(
      context: context,
      showDialogOnNoInternet: false,
      action: () async {
        final res =
            await _sb.rpc('mark_conversation_read', params: {'p_cid': cid});
        if (res is int) return res;
        if (res is num) return res.toInt();
        return 0;
      },
    );
  }

  // =========================
  // Conversations CRUD
  // =========================

  Future<_ConversationInfo> _getOrCreateSupportConversation({
    required String supportUserId,
    String? title,
  }) async {
    final session = context.read<AppSession>();

    final existing = await session.runNetworkGuarded<Map<String, dynamic>?>(
      context: context,
      action: () async {
        return await _sb
            .from('conversations')
            .select('id, title, user_id, counterparty_id')
            .eq('kind', 'support')
            .or(
              'and(user_id.eq.$_uid,counterparty_id.eq.$supportUserId),and(user_id.eq.$supportUserId,counterparty_id.eq.$_uid)',
            )
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      },
    );

    if (existing != null && (existing['id'] ?? '').toString().isNotEmpty) {
      final other = _resolveOtherPartyId(existing) ?? supportUserId;
      return _ConversationInfo(
        id: (existing['id'] as String),
        counterpartyId: other,
        title: (existing['title'] as String?)?.trim(),
      );
    }

    final inserted = await session.runNetworkGuarded<Map<String, dynamic>?>(
      context: context,
      action: () async {
        return await _sb
            .from('conversations')
            .insert({
              'kind': 'support',
              'user_id': _uid,
              'counterparty_id': supportUserId,
              'title': (title ?? _defaultTitleFor(ConversationKind.support))
                  .toString(),
            })
            .select('id, counterparty_id, title')
            .single();
      },
    );

    if (inserted == null) {
      throw Exception(
          widget.isAr ? 'لا يوجد اتصال بالإنترنت' : 'No internet connection');
    }

    return _ConversationInfo(
      id: (inserted['id'] as String),
      counterpartyId: (inserted['counterparty_id'] as String).trim(),
      title: (inserted['title'] as String?)?.trim(),
    );
  }

  Future<_ConversationInfo> _getOrCreatePropertyConversation({
    required String propertyId,
    String? reservationId,
    String? ownerId,
    String? title,
  }) async {
    final session = context.read<AppSession>();

    // resolve owner + title from properties if needed
    String? realOwner = ownerId;
    String? resolvedTitle = title;

    if ((realOwner ?? '').trim().isEmpty ||
        (resolvedTitle ?? '').trim().isEmpty) {
      final row = await session.runNetworkGuarded<Map<String, dynamic>?>(
        context: context,
        action: () async {
          return await _sb
              .from('properties')
              .select('owner_id, title')
              .eq('id', propertyId)
              .single();
        },
      );

      if (row == null) {
        throw Exception(
            widget.isAr ? 'لا يوجد اتصال بالإنترنت' : 'No internet connection');
      }

      realOwner = (realOwner ?? '').trim().isEmpty
          ? (row['owner_id'] as String?)?.trim()
          : realOwner;
      resolvedTitle = (resolvedTitle ?? '').trim().isEmpty
          ? (row['title'] as String?)?.trim()
          : resolvedTitle;
    }

    if ((realOwner ?? '').trim().isEmpty) {
      throw Exception(widget.isAr
          ? 'تعذر تحديد مالك العقار'
          : 'Failed to resolve property owner');
    }

    if (realOwner == _uid) {
      throw Exception(widget.isAr
          ? 'لا يمكن فتح دردشة لعقارك مع نفسك'
          : 'Cannot open chat with yourself');
    }

    final existing = await session.runNetworkGuarded<Map<String, dynamic>?>(
      context: context,
      action: () async {
        return await _sb
            .from('conversations')
            .select('id, title, user_id, counterparty_id')
            .eq('kind', 'property')
            .eq('property_id', propertyId)
            .or(
              'and(user_id.eq.$_uid,counterparty_id.eq.$realOwner),and(user_id.eq.$realOwner,counterparty_id.eq.$_uid)',
            )
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      },
    );

    if (existing != null && (existing['id'] ?? '').toString().isNotEmpty) {
      final other = _resolveOtherPartyId(existing) ?? realOwner!;
      final t = (existing['title'] as String?)?.trim();
      return _ConversationInfo(
        id: (existing['id'] as String),
        counterpartyId: other,
        title: t?.isNotEmpty == true ? t : resolvedTitle,
      );
    }

    final inserted = await session.runNetworkGuarded<Map<String, dynamic>?>(
      context: context,
      action: () async {
        return await _sb
            .from('conversations')
            .insert({
              'kind': 'property',
              'property_id': propertyId,
              'reservation_id': reservationId,
              'user_id': _uid,
              'counterparty_id': realOwner,
              'title':
                  (resolvedTitle ?? _defaultTitleFor(ConversationKind.property))
                      .toString(),
            })
            .select('id, counterparty_id, title')
            .single();
      },
    );

    if (inserted == null) {
      throw Exception(
          widget.isAr ? 'لا يوجد اتصال بالإنترنت' : 'No internet connection');
    }

    return _ConversationInfo(
      id: (inserted['id'] as String),
      counterpartyId: (inserted['counterparty_id'] as String).trim(),
      title: (inserted['title'] as String?)?.trim(),
    );
  }

  Future<void> _openConversationFromList(_ChatListRow row) async {
    final otherId = (row.otherUserId ?? '').trim();
    if (otherId.isEmpty) {
      _showSnack(widget.isAr
          ? 'تعذر فتح المحادثة: الطرف الآخر غير معروف'
          : 'Cannot open: unknown counterparty');
      return;
    }

    final kind = row.kind == 'support'
        ? ConversationKind.support
        : ConversationKind.property;
    final t = (row.title ?? '').trim().isNotEmpty
        ? row.title!.trim()
        : (row.otherFullName ?? '').trim().isNotEmpty
            ? row.otherFullName!.trim()
            : _defaultTitleFor(kind);

    setState(() {
      _activeConversationId = row.conversationId;
      _activeKind = kind;
      _activeTitle = t;
      _activeCounterpartyId = otherId;
      _tc.clear();
    });

    unawaited(_markReadSafe());
  }

  Future<void> _backToList() async {
    setState(() {
      _activeConversationId = null;
      _activeKind = null;
      _activeTitle = null;
      _activeCounterpartyId = null;
      _tc.clear();
      _listReloadTick++; // refresh list when returning
    });
  }

  // =========================
  // Messages: send
  // =========================

  Future<void> _sendMessage() async {
    final cid = (_activeConversationId ?? '').trim();
    if (cid.isEmpty || _sending) return;

    final txt = _tc.text.trim();
    if (txt.isEmpty) return;

    final receiverId = (_activeCounterpartyId ?? '').trim();
    if (receiverId.isEmpty) {
      _showSnack(widget.isAr
          ? 'تعذر تحديد الطرف الآخر لإرسال الرسالة'
          : 'Cannot determine receiver');
      return;
    }

    final session = context.read<AppSession>();

    setState(() => _sending = true);
    try {
      final ok = await session.runNetworkGuarded<bool>(
        context: context,
        action: () async {
          await _sb.from('messages').insert({
            'sender_id': _uid,
            'receiver_id': receiverId,
            'content': txt,
            'conversation_id': cid,
          });
          return true;
        },
      );

      if (ok != true) return;

      _tc.clear();

      // تحديث updated_at بدون تعطيل الواجهة
      unawaited(
        session.runNetworkGuarded<void>(
          context: context,
          action: () async {
            await _sb.from('conversations').update({
              'updated_at': DateTime.now().toUtc().toIso8601String()
            }).eq('id', cid);
          },
          showDialogOnNoInternet: false,
        ),
      );
    } catch (e) {
      _showSnack(widget.isAr ? 'فشل الإرسال: $e' : 'Send failed: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // =========================
  // WhatsApp-like: List via RPC
  // =========================

  Future<List<_ChatListRow>> _loadChatList() async {
    final session = context.read<AppSession>();

    final res = await session.runNetworkGuarded<dynamic>(
      context: context,
      action: () async {
        return await _sb.rpc('get_chat_list2', params: {'p_limit': 80});
      },
    );

    if (res == null) return <_ChatListRow>[];

    final List data = (res is List) ? res : <dynamic>[];
    return data
        .whereType<Map<String, dynamic>>()
        .map(_ChatListRow.fromMap)
        .where((r) => r.conversationId.trim().isNotEmpty)
        .toList();
  }

  // =========================
  // UI
  // =========================

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();

    // ✅ منع أي واجهة شبكية عند عدم وجود إنترنت
    if (!session.hasInternet) {
      return Directionality(
        textDirection: widget.isAr ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.isAr ? 'الدردشة' : 'Chat'),
          ),
          body: _NoInternetState(
            isAr: widget.isAr,
            onRetry: () {
              setState(() {
                _booting = true;
                _bootError = null;
                _bootStarted = false;
              });
              _boot();
            },
          ),
        ),
      );
    }

    return Directionality(
      textDirection: widget.isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_appTitle()),
          leading: (_activeConversationId ?? '').isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _backToList,
                )
              : null,
        ),
        body: _booting
            ? const Center(child: CircularProgressIndicator())
            : (_bootError != null)
                ? _ErrorState(
                    isAr: widget.isAr,
                    text: _bootError!,
                    onRetry: () {
                      setState(() {
                        _booting = true;
                        _bootError = null;
                        _bootStarted = false;
                      });
                      _boot();
                    },
                  )
                : (_activeConversationId ?? '').isEmpty
                    ? _ConversationsListRpc(
                        key: ValueKey(_listReloadTick),
                        isAr: widget.isAr,
                        load: _loadChatList,
                        onOpen: _openConversationFromList,
                      )
                    : _ChatThread(
                        isAr: widget.isAr,
                        sb: _sb,
                        conversationId: _activeConversationId!,
                        currentUserId: _uid,
                        onSend: _sendMessage,
                        onOpenedOrNewData: _markReadSafe,
                        controller: _tc,
                        sending: _sending,
                      ),
      ),
    );
  }

  String _appTitle() {
    if ((_activeConversationId ?? '').isNotEmpty) {
      final t = (_activeTitle ?? '').trim();
      if (t.isNotEmpty) return t;
      if (_activeKind == ConversationKind.support)
        return _defaultTitleFor(ConversationKind.support);
      return _defaultTitleFor(ConversationKind.property);
    }
    return widget.isAr ? 'المحادثات' : 'Chats';
  }
}

// =========================
// UI Widgets
// =========================

class _NoInternetState extends StatelessWidget {
  final bool isAr;
  final VoidCallback onRetry;

  const _NoInternetState({required this.isAr, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.wifi_off_rounded, size: 60, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          isAr ? 'لا يوجد اتصال بالإنترنت' : 'No Internet Connection',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          isAr
              ? 'تحقق من الاتصال ثم أعد المحاولة.'
              : 'Check your connection then try again.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 14),
        Center(
          child: ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(isAr ? 'إعادة المحاولة' : 'Retry'),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final bool isAr;
  final String text;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.isAr,
    required this.text,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.error_outline, size: 46, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          isAr ? 'تعذر فتح الدردشة' : 'Failed to open chat',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        Center(
          child: ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(isAr ? 'إعادة المحاولة' : 'Retry'),
          ),
        ),
      ],
    );
  }
}

/// ✅ قائمة محادثات مثل واتساب (RPC get_chat_list2)
class _ConversationsListRpc extends StatefulWidget {
  final bool isAr;
  final Future<List<_ChatListRow>> Function() load;
  final Future<void> Function(_ChatListRow row) onOpen;

  const _ConversationsListRpc({
    super.key,
    required this.isAr,
    required this.load,
    required this.onOpen,
  });

  @override
  State<_ConversationsListRpc> createState() => _ConversationsListRpcState();
}

class _ConversationsListRpcState extends State<_ConversationsListRpc> {
  late Future<List<_ChatListRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<List<_ChatListRow>>(
      future: _future,
      builder: (context, snap) {
        final waiting = snap.connectionState == ConnectionState.waiting;

        if (waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return Center(
              child: Text(widget.isAr
                  ? 'تعذر تحميل المحادثات'
                  : 'Failed to load chats'));
        }

        final rows = snap.data ?? const <_ChatListRow>[];

        if (rows.isEmpty) {
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const SizedBox(height: 70),
                Icon(Icons.forum_outlined,
                    size: 70, color: cs.onSurfaceVariant),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    widget.isAr ? 'لا توجد محادثات بعد' : 'No chats yet',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    widget.isAr
                        ? 'افتح إعلاناً ثم اختر مراسلة المعلن.'
                        : 'Open a listing then tap chat with owner.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final r = rows[i];

              final isSupport = r.kind == 'support';
              final name = (r.otherFullName ?? '').trim().isNotEmpty
                  ? r.otherFullName!.trim()
                  : (r.title ?? '').trim().isNotEmpty
                      ? r.title!.trim()
                      : (isSupport
                          ? (widget.isAr ? 'الدعم' : 'Support')
                          : (widget.isAr ? 'محادثة' : 'Chat'));

              final subtitle = (r.lastMessage ?? '').trim().isNotEmpty
                  ? r.lastMessage!.trim()
                  : (isSupport
                      ? (widget.isAr ? 'محادثة الدعم' : 'Support chat')
                      : (widget.isAr ? 'محادثة عقار' : 'Property chat'));

              final time = (r.lastMessageAt != null)
                  ? _fmtTimeLocal(r.lastMessageAt!)
                  : '';

              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => widget.onOpen(r),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: cs.outlineVariant.withOpacity(0.55)),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                        color: cs.shadow.withOpacity(0.07),
                      )
                    ],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isSupport
                              ? Colors.blue.withOpacity(0.12)
                              : Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          isSupport
                              ? Icons.support_agent
                              : Icons.home_work_outlined,
                          color: isSupport ? Colors.blue : Colors.green,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                ),
                                if (time.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    time,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                if (r.unreadCount > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      r.unreadCount > 99
                                          ? '99+'
                                          : r.unreadCount.toString(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: cs.onPrimary,
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _fmtTimeLocal(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// =========================
// Chat Thread (Messages)
// =========================

class _ChatThread extends StatefulWidget {
  final bool isAr;
  final SupabaseClient sb;
  final String conversationId;
  final String currentUserId;

  final TextEditingController controller;
  final Future<void> Function() onSend;
  final Future<void> Function() onOpenedOrNewData;
  final bool sending;

  const _ChatThread({
    required this.isAr,
    required this.sb,
    required this.conversationId,
    required this.currentUserId,
    required this.controller,
    required this.onSend,
    required this.onOpenedOrNewData,
    required this.sending,
  });

  @override
  State<_ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<_ChatThread> {
  final _scroll = ScrollController();

  Timer? _markReadDebounce;

  @override
  void initState() {
    super.initState();
    // ✅ عند فتح الثريد: علّم كمقروء
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.onOpenedOrNewData());
    });
  }

  @override
  void dispose() {
    _markReadDebounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _debouncedMarkRead() {
    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(widget.onOpenedOrNewData());
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final session = context.watch<AppSession>();

    if (!session.hasInternet) {
      return Center(
          child: Text(widget.isAr ? 'لا يوجد إنترنت' : 'No internet'));
    }

    if (widget.currentUserId.trim().isEmpty) {
      return Center(
          child: Text(widget.isAr
              ? 'سجّل الدخول لاستخدام الدردشة'
              : 'Login to use chat'));
    }

    final msgStream = widget.sb
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', widget.conversationId)
        .order('created_at', ascending: false);

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: msgStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Text(widget.isAr
                      ? 'تعذر تحميل الرسائل'
                      : 'Failed to load messages'),
                );
              }

              final rows = snap.data ?? const <Map<String, dynamic>>[];

              if (rows.isEmpty) {
                return Center(
                  child: Text(
                    widget.isAr
                        ? 'ابدأ المحادثة الآن'
                        : 'Start the conversation',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                );
              }

              // ✅ عند وصول بيانات جديدة: علّم كمقروء (debounced)
              _debouncedMarkRead();

              // scroll to bottom when new message arrives
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _scrollToBottom());

              return ListView.builder(
                controller: _scroll,
                reverse: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final m = rows[i];
                  final sender = (m['sender_id'] ?? '').toString();
                  final text = (m['content'] ?? '').toString();
                  final mine = sender == widget.currentUserId;

                  return Align(
                    alignment:
                        mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.78),
                      decoration: BoxDecoration(
                        color: mine ? cs.primaryContainer : cs.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: mine
                            ? null
                            : Border.all(
                                color: cs.outlineVariant.withOpacity(0.6)),
                      ),
                      child: Text(
                        text,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color:
                                  mine ? cs.onPrimaryContainer : cs.onSurface,
                            ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                  top: BorderSide(color: cs.outlineVariant.withOpacity(0.6))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText:
                          widget.isAr ? 'اكتب رسالة...' : 'Type a message...',
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withOpacity(0.6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => widget.onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: (widget.sending || !session.hasInternet)
                      ? null
                      : widget.onSend,
                  icon: widget.sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
