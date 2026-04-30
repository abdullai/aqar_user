// lib/screens/chat_page.dart
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../core/notifications/chat_message_sound.dart';
import '../core/notifications/in_app_notifications.dart';
import '../core/session/app_session.dart';
import '../core/workflow/listing_workflow.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_peer_service.dart';
import '../services/chat_presence_service.dart';
import '../services/org_team_service.dart';
import '../services/reservations_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/chat_peer_profile_sheet.dart';

enum ConversationKind { support, property, direct, agencyTeam, marketRequest }

enum _ChatInboxFilter { all, inquiries, personal, agency, support }

// ألوان قريبة من واتساب (خلفية المحادثة + فقاعات)
const Color _kWaChatBg = Color(0xFFECE5DD);
const Color _kWaBubbleSent = Color(0xFFDCF8C6);
const Color _kWaBubbleReceived = Color(0xFFFFFFFF);
const Color _kWaTimeColor = Color(0xFF667781);

DateTime? _parseMsgTs(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

String _fmtMsgTimeFromRow(Map<String, dynamic> m, {required bool isAr}) {
  final raw = m['created_at'];
  DateTime? dt;
  if (raw is String && raw.isNotEmpty) {
    dt = DateTime.tryParse(raw)?.toLocal();
  } else if (raw is DateTime) {
    dt = raw.toLocal();
  }
  if (dt == null) return '';
  final now = DateTime.now();
  final t = DateFormat.Hm().format(dt);
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return t;
  }
  final dPart = DateFormat.yMMMd(isAr ? 'ar' : 'en').format(dt);
  return '$dPart · $t';
}

String _chatInitialLetter(String name) {
  final t = name.trim();
  if (t.isEmpty) return '?';
  return t.substring(0, 1).toUpperCase();
}

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
  final String? otherAvatarUrl;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  /// عند kind = org_team_channel (من get_chat_list2).
  final String? orgId;

  const _ChatListRow({
    required this.conversationId,
    required this.kind,
    required this.title,
    required this.otherUserId,
    required this.otherFullName,
    required this.otherPhone,
    this.otherAvatarUrl,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    this.orgId,
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

    final orgRaw = m['org_id'];
    final orgStr =
        orgRaw == null ? '' : orgRaw.toString().trim();

    return _ChatListRow(
      conversationId: (m['conversation_id'] ?? '').toString(),
      kind: (m['kind'] ?? '').toString(),
      title: (m['title'] as String?)?.trim(),
      otherUserId: (m['other_user_id'] ?? '').toString().trim().isEmpty
          ? null
          : (m['other_user_id'] ?? '').toString().trim(),
      otherFullName: (m['other_full_name'] as String?)?.trim(),
      otherPhone: (m['other_phone'] as String?)?.trim(),
      otherAvatarUrl: (m['other_avatar_url'] as String?)?.trim(),
      lastMessage: (m['last_message'] as String?)?.trim(),
      lastMessageAt: dt,
      unreadCount: unread,
      orgId: orgStr.isEmpty ? null : orgStr,
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

  /// الطرف الآخر (المسوّق/الدعم). في محادثة العقار إذا لم يمرر يُستنتج من properties (مسوّق لا المالك).
  final String? counterpartyId;

  /// عنوان اختياري للمحادثة
  final String? title;

  /// نوع المحادثة عند الفتح المباشر بدون conversationId
  final ConversationKind? kind;

  /// UUID لحساب الدعم (messages.receiver_id NOT NULL)
  final String? supportUserId;

  /// طلب سوق (محادثة مع صاحب الطلب أو مع مقدّم عرض)
  final String? marketRequestId;

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
    this.marketRequestId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
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

  /// عرض في شريط الدردشة (صورة + اسم مثل واتساب)
  String? _peerDisplayName;
  String? _peerAvatarUrl;
  String? _peerLastSeenLine;

  final TextEditingController _tc = TextEditingController();
  bool _sending = false;

  bool _bootStarted = false;

  /// نبض «آخر ظهور» للمستخدم الحالي أثناء فتح شاشة الدردشة
  Timer? _presenceTimer;
  Timer? _peerSeenTimer;
  bool _presenceStarted = false;

  // list refresh key
  int _listReloadTick = 0;

  /// kind الخام من `conversations.kind` (مثل `org_team_channel`).
  String? _activeConversationKindRaw;

  /// `conversations.org_id` عند قناة الفريق.
  String? _activeOrgId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    _peerSeenTimer?.cancel();
    _tc.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ChatPresenceService.ping(_sb));
    }
  }

  void _schedulePresenceLoop() {
    if (_isGuest || _uid.isEmpty) return;
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(ChatPresenceService.ping(_sb));
    });
    unawaited(ChatPresenceService.ping(_sb));
  }

  void _schedulePeerSeenPolling(String peerId) {
    final id = peerId.trim();
    if (id.isEmpty) return;
    _peerSeenTimer?.cancel();
    _peerSeenTimer = Timer.periodic(const Duration(seconds: 32), (_) async {
      final row = await ChatPeerService.fetchProfile(_sb, id);
      if (!mounted) return;
      setState(() {
        _peerLastSeenLine =
            ChatPeerService.formatPresenceLine(row, widget.isAr);
      });
    });
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
    final k = (raw ?? '').toString().toLowerCase().trim();
    if (k == 'support') return ConversationKind.support;
    if (k == 'direct') return ConversationKind.direct;
    if (k == 'market_request') return ConversationKind.marketRequest;
    if (k == 'org_team_channel' ||
        k == 'org' ||
        k == 'team' ||
        k == 'agency' ||
        k == 'agency_team' ||
        k == 'organization') {
      return ConversationKind.agencyTeam;
    }
    return ConversationKind.property;
  }

  String _defaultTitleFor(ConversationKind kind) {
    if (kind == ConversationKind.support) {
      return widget.isAr ? 'دعم النظام' : 'System support';
    }
    if (kind == ConversationKind.direct) {
      return widget.isAr ? 'شخصي' : 'Personal';
    }
    if (kind == ConversationKind.agencyTeam) {
      return widget.isAr ? 'فريق / وسائط' : 'Agency & media';
    }
    if (kind == ConversationKind.marketRequest) {
      return widget.isAr ? 'طلب عقاري' : 'Property request';
    }
    return widget.isAr ? 'استفسارات إعلان' : 'Ad inquiries';
  }

  Future<void> _loadPeerProfile(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    try {
      final row = await ChatPeerService.fetchProfile(_sb, id);
      if (!mounted) return;
      setState(() {
        _peerDisplayName = ChatPeerService.displayName(row, widget.isAr);
        final av = (row?['avatar_url'] ?? '').toString().trim();
        _peerAvatarUrl = av.isNotEmpty ? av : null;
        _peerLastSeenLine =
            ChatPeerService.formatPresenceLine(row, widget.isAr);
      });
    } catch (_) {}
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
                .select('id, kind, title, user_id, counterparty_id, org_id')
                .eq('id', directCid)
                .maybeSingle();
          },
        );

        if (conv == null) {
          throw Exception(
              widget.isAr ? 'المحادثة غير موجودة' : 'Conversation not found');
        }

        final kindStr = (conv['kind'] ?? '').toString().toLowerCase().trim();
        if (kindStr == 'org_team_channel') {
          final ownerId = (conv['user_id'] ?? '').toString().trim();
          final orgId = conv['org_id'] == null
              ? ''
              : conv['org_id'].toString().trim();
          if (orgId.isEmpty) {
            throw Exception(widget.isAr
                ? 'محادثة قناة الفريق غير مكتملة على الخادم'
                : 'Team channel conversation is not configured');
          }
          final peer =
              ownerId.isNotEmpty ? ownerId : (_uid.isNotEmpty ? _uid : '');
          setState(() {
            _activeConversationId = (conv['id'] ?? '').toString();
            _activeConversationKindRaw = 'org_team_channel';
            _activeOrgId = orgId;
            _activeKind = _parseKind('org_team_channel');
            _activeTitle = (conv['title'] as String?)?.trim();
            _activeCounterpartyId = peer.isNotEmpty ? peer : null;
            _booting = false;
          });
          if (peer.isNotEmpty) {
            unawaited(_loadPeerProfile(peer));
            _schedulePeerSeenPolling(peer);
          }
          unawaited(_markReadSafe());
          return;
        }

        final otherPartyId = _resolveOtherPartyId(conv);
        if (otherPartyId == null || otherPartyId.trim().isEmpty) {
          throw Exception(widget.isAr
              ? 'تعذر تحديد الطرف الآخر'
              : 'Cannot resolve other party');
        }

        setState(() {
          _activeConversationId = (conv['id'] ?? '').toString();
          _activeConversationKindRaw = (conv['kind'] ?? '').toString();
          _activeOrgId = conv['org_id'] == null
              ? null
              : conv['org_id'].toString().trim().isEmpty
                  ? null
                  : conv['org_id'].toString().trim();
          _activeKind = _parseKind(conv['kind']);
          _activeTitle = (conv['title'] as String?)?.trim();
          _activeCounterpartyId = otherPartyId;
          _booting = false;
        });

        unawaited(_loadPeerProfile(otherPartyId));
        _schedulePeerSeenPolling(otherPartyId);
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
          title: widget.title,
        );

        setState(() {
          _activeConversationId = info.id;
          _activeKind = ConversationKind.property;
          _activeConversationKindRaw = 'property';
          _activeOrgId = null;
          _activeTitle = (info.title ?? '').trim().isEmpty
              ? _defaultTitleFor(ConversationKind.property)
              : info.title!.trim();
          _activeCounterpartyId = info.counterpartyId;
          _booting = false;
        });

        unawaited(_loadPeerProfile(info.counterpartyId));
        _schedulePeerSeenPolling(info.counterpartyId);
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
          _activeConversationKindRaw = 'support';
          _activeOrgId = null;
          _activeTitle = (info.title ?? '').trim().isEmpty
              ? _defaultTitleFor(ConversationKind.support)
              : info.title!.trim();
          _activeCounterpartyId = info.counterpartyId; // = supportId
          _booting = false;
        });

        unawaited(_loadPeerProfile(info.counterpartyId));
        _schedulePeerSeenPolling(info.counterpartyId);
        unawaited(_markReadSafe());
        return;
      }

      // 3b) محادثة مباشرة مع عضو فريق (نفس المؤسسة)
      if (widget.kind == ConversationKind.direct) {
        final peer = (widget.counterpartyId ?? '').trim();
        if (peer.isEmpty) {
          throw Exception(widget.isAr
              ? 'تعذر فتح المحادثة: الطرف الآخر غير محدد'
              : 'Cannot open chat: peer not set');
        }

        final info = await _ensureDirectConversationWithPeer(peer);

        setState(() {
          _activeConversationId = info.id;
          _activeKind = ConversationKind.direct;
          _activeConversationKindRaw = 'direct';
          _activeOrgId = null;
          _activeTitle = (info.title ?? '').trim().isEmpty
              ? _defaultTitleFor(ConversationKind.direct)
              : info.title!.trim();
          _activeCounterpartyId = info.counterpartyId;
          _booting = false;
        });

        unawaited(_loadPeerProfile(info.counterpartyId));
        _schedulePeerSeenPolling(info.counterpartyId);
        unawaited(_markReadSafe());
        return;
      }

      // 3c) محادثة طلب سوق
      if (widget.kind == ConversationKind.marketRequest &&
          (widget.marketRequestId ?? '').trim().isNotEmpty) {
        final peerOpt = (widget.counterpartyId ?? '').trim();
        final cid = await session.runNetworkGuarded<String?>(
          context: context,
          action: () async {
            return ReservationsService.getOrCreateMarketRequestConversation(
              marketRequestId: widget.marketRequestId!.trim(),
              counterpartyId: peerOpt.isEmpty ? null : peerOpt,
            );
          },
        );

        if (cid == null || cid.isEmpty) {
          throw Exception(widget.isAr
              ? 'لا يوجد اتصال أو تعذر فتح المحادثة'
              : 'Offline or could not open chat');
        }

        final conv = await session.runNetworkGuarded<Map<String, dynamic>?>(
          context: context,
          action: () async {
            return _sb
                .from('conversations')
                .select('user_id, counterparty_id, title')
                .eq('id', cid)
                .maybeSingle();
          },
        );

        if (conv == null) {
          throw Exception(
              widget.isAr ? 'المحادثة غير موجودة' : 'Conversation missing');
        }

        final otherPartyId = _resolveOtherPartyId(conv);
        if (otherPartyId == null || otherPartyId.trim().isEmpty) {
          throw Exception(widget.isAr
              ? 'تعذر تحديد الطرف الآخر'
              : 'Cannot resolve other party');
        }

        final t = (conv['title'] as String?)?.trim();

        setState(() {
          _activeConversationId = cid;
          _activeKind = ConversationKind.marketRequest;
          _activeConversationKindRaw = 'market_request';
          _activeOrgId = null;
          _activeTitle = (t ?? '').isEmpty
              ? _defaultTitleFor(ConversationKind.marketRequest)
              : t!;
          _activeCounterpartyId = otherPartyId;
          _booting = false;
        });

        unawaited(_loadPeerProfile(otherPartyId));
        _schedulePeerSeenPolling(otherPartyId);
        unawaited(_markReadSafe());
        return;
      }

      // 4) قائمة المحادثات
      setState(() {
        _activeConversationId = null;
        _activeKind = null;
        _activeConversationKindRaw = null;
        _activeOrgId = null;
        _activeTitle = null;
        _activeCounterpartyId = null;
        _booting = false;
      });
    } catch (e) {
      setState(() {
        _booting = false;
        _bootError = e.toString();
      });
    } finally {
      if (mounted && !_booting && _bootError == null && !_isGuest) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_presenceStarted) {
            _presenceStarted = true;
            _schedulePresenceLoop();
          }
        });
      }
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
        try {
          await _sb
              .rpc('mark_chat_messages_read_receipts', params: {'p_cid': cid});
        } catch (_) {}
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
    String? title,
  }) async {
    final session = context.read<AppSession>();

    // counterparty دائماً المسوّق من الصف (لا نستخدم ownerId المُمرَّر قديماً كطرف).
    String? resolvedTitle = title;

    final row = await session.runNetworkGuarded<Map<String, dynamic>?>(
      context: context,
      action: () async {
        return await _sb
            .from('properties')
            .select(
              'owner_id, title, published_by_marketer_id, selected_marketer_id',
            )
            .eq('id', propertyId)
            .single();
      },
    );

    if (row == null) {
      throw Exception(
          widget.isAr ? 'لا يوجد اتصال بالإنترنت' : 'No internet connection');
    }

    final marketerId =
        ReservationsService.marketerCounterpartyIdForPropertyChat(
      Map<String, dynamic>.from(row),
    );
    if ((resolvedTitle ?? '').trim().isEmpty) {
      resolvedTitle = (row['title'] as String?)?.trim();
    }

    if ((marketerId ?? '').trim().isEmpty) {
      throw Exception(widget.isAr
          ? 'لا يوجد مسوّق مسؤول عن هذا الإعلان. التواصل يكون مع المسوّق فقط.'
          : 'No marketer is assigned to this listing. Chat is with the marketer only.');
    }

    if (marketerId == _uid) {
      throw Exception(widget.isAr
          ? 'لا يمكن فتح دردشة مع نفسك'
          : 'Cannot open chat with yourself');
    }

    // محادثة واحدة لكل عقار لحسابك: أي صف property بنفس property_id تشارك فيه أنت.
    final existing = await session.runNetworkGuarded<Map<String, dynamic>?>(
      context: context,
      action: () async {
        return await _sb
            .from('conversations')
            .select('id, title, user_id, counterparty_id')
            .eq('kind', 'property')
            .eq('property_id', propertyId)
            .or('user_id.eq.$_uid,counterparty_id.eq.$_uid')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      },
    );

    if (existing != null && (existing['id'] ?? '').toString().isNotEmpty) {
      final other = _resolveOtherPartyId(existing) ?? marketerId!;
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
              'counterparty_id': marketerId,
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

  Future<_ConversationInfo> _ensureDirectConversationWithPeer(
      String peerId) async {
    final session = context.read<AppSession>();
    final trimmed = peerId.trim();
    final svc = OrgTeamService(_sb);
    final fromRpc = await svc.ensureDirectConversation(trimmed);
    if (fromRpc != null && fromRpc.isNotEmpty) {
      return _ConversationInfo(
        id: fromRpc,
        counterpartyId: trimmed,
        title:
            (widget.title ?? '').trim().isEmpty ? null : widget.title!.trim(),
      );
    }
    return _getOrCreateDirectConversationClient(trimmed, session);
  }

  Future<_ConversationInfo> _getOrCreateDirectConversationClient(
    String peerId,
    AppSession session,
  ) async {
    final existing = await session.runNetworkGuarded<Map<String, dynamic>?>(
      context: context,
      action: () async {
        return await _sb
            .from('conversations')
            .select('id, title, user_id, counterparty_id')
            .eq('kind', 'direct')
            .or(
              'and(user_id.eq.$_uid,counterparty_id.eq.$peerId),and(user_id.eq.$peerId,counterparty_id.eq.$_uid)',
            )
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      },
    );

    if (existing != null && (existing['id'] ?? '').toString().isNotEmpty) {
      final other = _resolveOtherPartyId(existing) ?? peerId;
      return _ConversationInfo(
        id: (existing['id'] as String),
        counterpartyId: other,
        title: (existing['title'] as String?)?.trim(),
      );
    }

    final titleStr = (widget.title ?? '').trim().isEmpty
        ? _defaultTitleFor(ConversationKind.direct)
        : widget.title!.trim();

    final inserted = await session.runNetworkGuarded<Map<String, dynamic>?>(
      context: context,
      action: () async {
        return await _sb
            .from('conversations')
            .insert({
              'kind': 'direct',
              'user_id': _uid,
              'counterparty_id': peerId,
              'title': titleStr,
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
    final kindLower = row.kind.toLowerCase().trim();
    final otherId = (row.otherUserId ?? '').trim();
    if (otherId.isEmpty && kindLower != 'org_team_channel') {
      _showSnack(widget.isAr
          ? 'تعذر فتح المحادثة: الطرف الآخر غير معروف'
          : 'Cannot open: unknown counterparty');
      return;
    }

    final kind = _parseKind(row.kind);
    final t = (row.title ?? '').trim().isNotEmpty
        ? row.title!.trim()
        : (row.otherFullName ?? '').trim().isNotEmpty
            ? row.otherFullName!.trim()
            : _defaultTitleFor(kind);

    final displayName = (row.otherFullName ?? '').trim().isNotEmpty
        ? row.otherFullName!.trim()
        : t;

    setState(() {
      _activeConversationId = row.conversationId;
      _activeKind = kind;
      _activeConversationKindRaw = row.kind;
      _activeOrgId = row.orgId;
      _activeTitle = t;
      _activeCounterpartyId = otherId.isNotEmpty ? otherId : null;
      _peerDisplayName = displayName;
      _peerAvatarUrl = row.otherAvatarUrl;
      _tc.clear();
    });

    if (otherId.isNotEmpty) {
      unawaited(_loadPeerProfile(otherId));
      _schedulePeerSeenPolling(otherId);
    }
    unawaited(_markReadSafe());
  }

  Future<void> _backToList() async {
    _peerSeenTimer?.cancel();
    setState(() {
      _activeConversationId = null;
      _activeKind = null;
      _activeConversationKindRaw = null;
      _activeOrgId = null;
      _activeTitle = null;
      _activeCounterpartyId = null;
      _peerDisplayName = null;
      _peerAvatarUrl = null;
      _peerLastSeenLine = null;
      _tc.clear();
      _listReloadTick++; // refresh list when returning
    });
  }

  // =========================
  // Messages: send
  // =========================

  Future<void> _sendMessage() async {
    final txt = _tc.text.trim();
    if (txt.isEmpty) return;
    await _sendChatPayload(
      content: txt,
      clearInput: true,
    );
  }

  /// إرسال نص و/أو مرفق (صورة، موقع، إلخ) — يُحدّث الإشعار الداخلي للمستلم.
  Future<void> _sendChatPayload({
    required String content,
    String? attachmentUrl,
    String? attachmentType,
    bool clearInput = false,
  }) async {
    final cid = (_activeConversationId ?? '').trim();
    if (cid.isEmpty || _sending) return;

    final trimmed = content.trim();
    if (trimmed.isEmpty &&
        (attachmentUrl == null || attachmentUrl.trim().isEmpty)) {
      return;
    }

    if ((_activeConversationKindRaw ?? '').toLowerCase().trim() ==
        'org_team_channel') {
      final orgId = (_activeOrgId ?? '').trim();
      if (orgId.isEmpty) {
        if (mounted) {
          _showSnack(widget.isAr
              ? 'تعذر تحديد المؤسسة'
              : 'Organization not set');
        }
        return;
      }
      if ((attachmentUrl ?? '').trim().isNotEmpty) {
        if (mounted) {
          _showSnack(widget.isAr
              ? 'قناة الفريق: النص فقط في هذه المرحلة'
              : 'Team channel: text only for now');
        }
        return;
      }
      if (trimmed.isEmpty) return;

      final session = context.read<AppSession>();
      setState(() => _sending = true);
      try {
        final ok = await session.runNetworkGuarded<bool>(
          context: context,
          action: () async {
            return await OrgTeamService(_sb).insertOrgTeamChannelPost(
              orgId: orgId,
              body: trimmed,
            );
          },
        );
        if (ok != true || !mounted) return;
        if (clearInput) _tc.clear();
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
        if (mounted) {
          _showSnack(widget.isAr ? 'فشل الإرسال: $e' : 'Send failed: $e');
        }
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      return;
    }

    final receiverId = (_activeCounterpartyId ?? '').trim();
    if (receiverId.isEmpty) {
      _showSnack(widget.isAr
          ? 'تعذر تحديد الطرف الآخر لإرسال الرسالة'
          : 'Cannot determine receiver');
      return;
    }

    final session = context.read<AppSession>();
    final displayBody =
        trimmed.isNotEmpty ? trimmed : (widget.isAr ? 'مرفق' : 'Attachment');

    setState(() => _sending = true);
    try {
      Future<bool> insertOnce(Map<String, dynamic> payload) async {
        final res = await session.runNetworkGuarded<bool>(
          context: context,
          action: () async {
            await _sb.from('messages').insert(payload);
            return true;
          },
        );
        return res == true;
      }

      final payload = <String, dynamic>{
        'sender_id': _uid,
        'receiver_id': receiverId,
        'conversation_id': cid,
        'content': trimmed.isEmpty ? ' ' : trimmed,
      };
      final au = attachmentUrl?.trim() ?? '';
      final at = attachmentType?.trim().toLowerCase() ?? '';
      if (au.isNotEmpty) {
        payload['attachment_url'] = au;
        if (at.isNotEmpty) payload['attachment_type'] = at;
      }

      var ok = await insertOnce(payload);
      if (!ok && au.isNotEmpty) {
        payload.remove('attachment_url');
        payload.remove('attachment_type');
        if (trimmed.isEmpty) {
          payload['content'] = '${widget.isAr ? 'مرفق' : 'Attachment'}\n$au';
        }
        ok = await insertOnce(payload);
      }

      if (!ok) return;

      if (clearInput) _tc.clear();

      try {
        await InAppNotificationWriter.insert(
          _sb,
          userId: receiverId,
          type: InAppNotifTypes.chatMessage,
          data: {
            WorkflowNotificationKeys.role: 'peer',
            WorkflowNotificationKeys.mainTab: WorkflowMainSections.chat,
            WorkflowNotificationKeys.deepRoute: InAppDeepRoutes.chat,
            InAppDataKeys.conversationId: cid,
            'kind': InAppNotifTypes.chatMessage,
            'counterparty_id': _uid,
            'sender_id': _uid,
            'title_ar': 'رسالة جديدة',
            'title_en': 'New message',
            'body_ar': displayBody.length > 100
                ? '${displayBody.substring(0, 100)}…'
                : displayBody,
            'body_en': displayBody.length > 100
                ? '${displayBody.substring(0, 100)}…'
                : displayBody,
          },
        );
      } catch (_) {}

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

  Future<void> _onAttachmentMenu(String kind) async {
    if ((_activeConversationKindRaw ?? '').toLowerCase().trim() ==
        'org_team_channel') {
      _showSnack(widget.isAr
          ? 'قناة الفريق: النص فقط حالياً'
          : 'Team channel: text only for now');
      return;
    }
    switch (kind) {
      case 'media':
        await _attachSendImage();
        break;
      case 'loc':
        await _attachSendLocation();
        break;
      case 'contact':
        await _attachShareContact();
        break;
      default:
        break;
    }
  }

  Future<void> _attachSendImage() async {
    if ((_activeConversationKindRaw ?? '').toLowerCase().trim() ==
        'org_team_channel') {
      _showSnack(widget.isAr
          ? 'قناة الفريق: النص فقط حالياً'
          : 'Team channel: text only for now');
      return;
    }
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    if (bytes.isEmpty) return;
    final cid = (_activeConversationId ?? '').trim();
    if (cid.isEmpty) return;
    // نفس بادئة 20260472_storage_market_request_covers.sql حتى تعمل RLS دون سياسات chat_uploads إضافية.
    final path = 'market-requests/$_uid/chat/$cid/${const Uuid().v4()}.jpg';
    try {
      await _sb.storage.from('property-images').uploadBinary(
            path,
            bytes,
            fileOptions:
                const FileOptions(upsert: true, contentType: 'image/jpeg'),
          );
      final url = _sb.storage.from('property-images').getPublicUrl(path);
      final cap = _tc.text.trim();
      await _sendChatPayload(
        content: cap,
        attachmentUrl: url,
        attachmentType: 'image',
        clearInput: cap.isNotEmpty,
      );
    } catch (e) {
      if (mounted) {
        _showSnack(widget.isAr
            ? 'تعذّر رفع الصورة. تحقق من الصلاحيات أو حجم الملف.\n$e'
            : 'Could not upload image.\n$e');
      }
    }
  }

  Future<void> _attachSendLocation() async {
    if ((_activeConversationKindRaw ?? '').toLowerCase().trim() ==
        'org_team_channel') {
      _showSnack(widget.isAr
          ? 'قناة الفريق: النص فقط حالياً'
          : 'Team channel: text only for now');
      return;
    }
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          _showSnack(widget.isAr
              ? 'يلزم السماح بالموقع لإرساله.'
              : 'Location permission is required.');
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final url =
          'https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}';
      final line =
          widget.isAr ? '📍 موقعي الحالي: $url' : '📍 My location: $url';
      await _sendChatPayload(
        content: line,
        attachmentUrl: url,
        attachmentType: 'location',
      );
    } catch (e) {
      if (mounted) {
        _showSnack(
            widget.isAr ? 'تعذّر جلب الموقع: $e' : 'Location failed: $e');
      }
    }
  }

  Future<void> _attachShareContact() async {
    if ((_activeConversationKindRaw ?? '').toLowerCase().trim() ==
        'org_team_channel') {
      _showSnack(widget.isAr
          ? 'قناة الفريق: النص فقط حالياً'
          : 'Team channel: text only for now');
      return;
    }
    final phoneCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(widget.isAr ? 'مشاركة رقم' : 'Share a number'),
          content: TextField(
            controller: phoneCtl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: widget.isAr ? '+966…' : '+966…',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(widget.isAr ? 'إرسال' : 'Send'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    final raw = phoneCtl.text.trim();
    phoneCtl.dispose();
    if (raw.isEmpty) return;
    final line = widget.isAr ? '📇 جهة اتصال: $raw' : '📇 Contact: $raw';
    await _sendChatPayload(
      content: line,
      attachmentType: 'contact',
    );
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
    final rows = data
        .whereType<Map<String, dynamic>>()
        .map(_ChatListRow.fromMap)
        .where((r) => r.conversationId.trim().isNotEmpty)
        .toList();

    final ids = rows
        .map((r) => r.otherUserId)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return rows;

    final profiles = await ChatPeerService.fetchProfilesBatch(_sb, ids);
    return rows.map((r) {
      final oid = r.otherUserId ?? '';
      final p = profiles[oid];
      if (p == null) return r;
      final av = (p['avatar_url'] ?? '').toString().trim();
      final dn = ChatPeerService.displayName(p, widget.isAr);
      final nameOk = (r.otherFullName ?? '').trim().isNotEmpty;
      return _ChatListRow(
        conversationId: r.conversationId,
        kind: r.kind,
        title: r.title,
        otherUserId: r.otherUserId,
        otherFullName: nameOk ? r.otherFullName : dn,
        otherPhone: r.otherPhone,
        otherAvatarUrl: av.isNotEmpty ? av : r.otherAvatarUrl,
        lastMessage: r.lastMessage,
        lastMessageAt: r.lastMessageAt,
        unreadCount: r.unreadCount,
        orgId: r.orgId,
      );
    }).toList();
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
          title: (_activeConversationId ?? '').isNotEmpty
              ? _ChatAppBarLead(
                  name: _threadBarTitle(),
                  subtitle: _threadBarSubtitle(),
                  avatarUrl: _peerAvatarUrl,
                  onTap: () {
                    final id = (_activeCounterpartyId ?? '').trim();
                    if (id.isEmpty) return;
                    showChatPeerProfileSheet(
                      context: context,
                      isAr: widget.isAr,
                      userId: id,
                      supabase: _sb,
                    );
                  },
                )
              : Text(_appTitle()),
          leading: (_activeConversationId ?? '').isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _backToList,
                )
              : null,
        ),
        body: _booting
            ? const Center(child: AppLogoLoading())
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
                        onAttachmentSelected: _onAttachmentMenu,
                        attachmentsEnabled:
                            (_activeConversationKindRaw ?? '')
                                    .toLowerCase()
                                    .trim() !=
                                'org_team_channel',
                        composerHint:
                            (_activeConversationKindRaw ?? '')
                                        .toLowerCase()
                                        .trim() ==
                                    'org_team_channel'
                                ? (widget.isAr
                                    ? 'اكتب منشوراً للفريق…'
                                    : 'Post to the team…')
                                : null,
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
      if (_activeKind == ConversationKind.support) {
        return _defaultTitleFor(ConversationKind.support);
      }
      if (_activeKind == ConversationKind.direct) {
        return _defaultTitleFor(ConversationKind.direct);
      }
      if (_activeKind == ConversationKind.agencyTeam) {
        return _defaultTitleFor(ConversationKind.agencyTeam);
      }
      if (_activeKind == ConversationKind.marketRequest) {
        return _defaultTitleFor(ConversationKind.marketRequest);
      }
      return _defaultTitleFor(ConversationKind.property);
    }
    return widget.isAr ? 'المحادثات' : 'Chats';
  }

  String _threadBarTitle() {
    if ((_activeConversationKindRaw ?? '').toLowerCase().trim() ==
        'org_team_channel') {
      final t = (_activeTitle ?? '').trim();
      if (t.isNotEmpty) return t;
      return widget.isAr ? 'قناة الفريق' : 'Team channel';
    }
    final n = (_peerDisplayName ?? '').trim();
    if (n.isNotEmpty) return n;
    final t = (_activeTitle ?? '').trim();
    if (_activeKind == ConversationKind.property) {
      final cp = (_activeCounterpartyId ?? '').trim();
      if (cp.isNotEmpty) {
        return widget.isAr ? 'مسوّق الإعلان' : 'Listing marketer';
      }
      return widget.isAr ? 'دردشة العقار' : 'Property chat';
    }
    if (t.isNotEmpty) return t;
    if (_activeKind == ConversationKind.support) {
      return _defaultTitleFor(ConversationKind.support);
    }
    if (_activeKind == ConversationKind.direct) {
      return _defaultTitleFor(ConversationKind.direct);
    }
    if (_activeKind == ConversationKind.agencyTeam) {
      return _defaultTitleFor(ConversationKind.agencyTeam);
    }
    if (_activeKind == ConversationKind.marketRequest) {
      return _defaultTitleFor(ConversationKind.marketRequest);
    }
    return _defaultTitleFor(ConversationKind.property);
  }

  /// السطر الثاني: للعقار يظهر عنوان الإعلان + آخر ظهور؛ غير ذلك يبقى «آخر ظهور» فقط.
  String? _threadBarSubtitle() {
    if ((_activeConversationKindRaw ?? '').toLowerCase().trim() ==
        'org_team_channel') {
      return widget.isAr
          ? 'منشورات الأعضاء النشطين'
          : 'Posts to all active members';
    }
    final seen = (_peerLastSeenLine ?? '').trim();
    if (_activeKind == ConversationKind.property) {
      final prop = (_activeTitle ?? '').trim();
      if (prop.isNotEmpty) {
        final pfx = widget.isAr ? 'العقار' : 'Listing';
        if (seen.isNotEmpty) {
          return '$pfx: $prop\n$seen';
        }
        return '$pfx: $prop';
      }
    }
    return seen.isEmpty ? null : seen;
  }
}

/// شريط علوي داخل المحادثة: صورة + اسم (مثل واتساب) — الضغط يفتح بيانات المستخدم.
class _ChatAppBarLead extends StatelessWidget {
  final String name;
  final String? subtitle;
  final String? avatarUrl;
  final VoidCallback onTap;

  const _ChatAppBarLead({
    required this.name,
    this.subtitle,
    required this.avatarUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = (subtitle ?? '').trim();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: cs.primaryContainer,
              backgroundImage: (avatarUrl ?? '').trim().isNotEmpty
                  ? CachedNetworkImageProvider(avatarUrl!.trim())
                  : null,
              child: (avatarUrl ?? '').trim().isEmpty
                  ? Text(
                      _chatInitialLetter(name),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cs.onPrimaryContainer,
                        fontSize: 16,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatListAvatar extends StatelessWidget {
  final bool isSupport;
  final bool isOrgTeamChannel;
  final String name;
  final String? avatarUrl;

  const _ChatListAvatar({
    required this.isSupport,
    this.isOrgTeamChannel = false,
    required this.name,
    required this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (isOrgTeamChannel) {
      return CircleAvatar(
        radius: 26,
        backgroundColor: cs.primary.withValues(alpha: 0.12),
        child: Icon(
          Icons.campaign_outlined,
          color: cs.primary,
          size: 28,
        ),
      );
    }
    if (isSupport) {
      return CircleAvatar(
        radius: 26,
        backgroundColor: Colors.blue.withOpacity(0.15),
        child: Icon(
          Icons.support_agent,
          color: Colors.blue.shade700,
          size: 28,
        ),
      );
    }
    final url = (avatarUrl ?? '').trim();
    if (url.isNotEmpty) {
      return CircleAvatar(
        radius: 26,
        backgroundColor: cs.primaryContainer,
        backgroundImage: CachedNetworkImageProvider(url),
      );
    }
    return CircleAvatar(
      radius: 26,
      backgroundColor: cs.primaryContainer,
      child: Text(
        _chatInitialLetter(name),
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 20,
          color: cs.onPrimaryContainer,
        ),
      ),
    );
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
  _ChatInboxFilter _filter = _ChatInboxFilter.all;

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

  bool _isAgencyKind(String raw) {
    final k = raw.toLowerCase().trim();
    return k == 'org_team_channel' ||
        k == 'org' ||
        k == 'team' ||
        k == 'agency' ||
        k == 'agency_team' ||
        k == 'organization';
  }

  bool _rowMatches(_ChatListRow r) {
    switch (_filter) {
      case _ChatInboxFilter.all:
        return true;
      case _ChatInboxFilter.inquiries:
        if (r.kind == 'support' || r.kind == 'direct') return false;
        return !_isAgencyKind(r.kind);
      case _ChatInboxFilter.personal:
        return r.kind == 'direct';
      case _ChatInboxFilter.agency:
        return _isAgencyKind(r.kind);
      case _ChatInboxFilter.support:
        return r.kind == 'support';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<List<_ChatListRow>>(
      future: _future,
      builder: (context, snap) {
        final waiting = snap.connectionState == ConnectionState.waiting;

        if (waiting) {
          return const Center(child: AppLogoLoading());
        }

        if (snap.hasError) {
          return Center(
              child: Text(widget.isAr
                  ? 'تعذر تحميل المحادثات'
                  : 'Failed to load chats'));
        }

        final rows = snap.data ?? const <_ChatListRow>[];
        final filtered = rows.where(_rowMatches).toList();

        Widget filterBar() {
          String lab(_ChatInboxFilter f) {
            switch (f) {
              case _ChatInboxFilter.all:
                return widget.isAr ? 'الكل' : 'All';
              case _ChatInboxFilter.inquiries:
                return widget.isAr ? 'الإعلان' : 'Ads';
              case _ChatInboxFilter.personal:
                return widget.isAr ? 'شخصي' : 'Personal';
              case _ChatInboxFilter.agency:
                return widget.isAr ? 'الفريق' : 'Team';
              case _ChatInboxFilter.support:
                return widget.isAr ? 'الدعم' : 'Support';
            }
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in _ChatInboxFilter.values)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(
                        label: Text(lab(f)),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
          );
        }

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
                        ? 'افتح إعلاناً ثم اختر مراسلة المسوّق.'
                        : 'Open a listing, then tap chat with the marketer.',
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

        if (filtered.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              filterBar(),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.isAr
                          ? 'لا محادثات في هذا القسم'
                          : 'No conversations in this section',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            filterBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 76,
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                  ),
                  itemBuilder: (context, i) {
                    final r = filtered[i];
                    final loc = AppLocalizations.of(context);

                    final isSupport = r.kind == 'support';
                    final isDirect = r.kind == 'direct';
                    final isAgency = _isAgencyKind(r.kind);
                    final isOrgChannel =
                        r.kind.toLowerCase().trim() == 'org_team_channel';
                    final name = isOrgChannel
                        ? ((r.title ?? '').trim().isNotEmpty
                            ? r.title!.trim()
                            : (widget.isAr ? 'قناة الفريق' : 'Team channel'))
                        : (r.otherFullName ?? '').trim().isNotEmpty
                            ? r.otherFullName!.trim()
                            : (r.title ?? '').trim().isNotEmpty
                                ? r.title!.trim()
                                : (isSupport
                                    ? (widget.isAr ? 'الدعم' : 'Support')
                                    : isDirect
                                        ? (loc?.chatListKindDirect ??
                                            (widget.isAr
                                                ? 'شخصي'
                                                : 'Personal'))
                                        : isAgency
                                            ? (widget.isAr
                                                ? 'فريق'
                                                : 'Agency')
                                            : (widget.isAr
                                                ? 'محادثة'
                                                : 'Chat'));

                    final subtitle = (r.lastMessage ?? '').trim().isNotEmpty
                        ? r.lastMessage!.trim()
                        : (isOrgChannel
                            ? (widget.isAr
                                ? 'منشورات جماعية'
                                : 'Team broadcast')
                            : isSupport
                                ? (widget.isAr
                                    ? 'محادثة الدعم'
                                    : 'Support chat')
                                : isDirect
                                    ? (loc?.chatKindDirect ??
                                        (widget.isAr
                                            ? 'شخصي'
                                            : 'Personal chat'))
                                    : isAgency
                                        ? (widget.isAr
                                            ? 'فريق ووسائط'
                                            : 'Team & files')
                                        : (widget.isAr
                                            ? 'استفسار إعلان'
                                            : 'Ad inquiry'));

                    final time = (r.lastMessageAt != null)
                        ? _fmtTimeLocal(r.lastMessageAt!)
                        : '';

                    final av = (r.otherAvatarUrl ?? '').trim();

                    return Material(
                      color: cs.surface,
                      child: InkWell(
                        onTap: () => widget.onOpen(r),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ChatListAvatar(
                                isSupport: isSupport,
                                isOrgTeamChannel: isOrgChannel,
                                name: name,
                                avatarUrl: av.isNotEmpty ? av : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 16,
                                                ),
                                          ),
                                        ),
                                        if (time.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Text(
                                            time,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                  fontWeight: FontWeight.w600,
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
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                        if (r.unreadCount > 0) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF25D366),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              r.unreadCount > 99
                                                  ? '99+'
                                                  : r.unreadCount.toString(),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 11,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
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

/// علامات واتساب: ✓ مرسل، ✓✓ وصل، ✓✓ مقروء (للرسائل الصادرة فقط).
class _WaReceiptTicks extends StatelessWidget {
  final DateTime? readAt;
  final DateTime? deliveredAt;

  const _WaReceiptTicks({required this.readAt, required this.deliveredAt});

  @override
  Widget build(BuildContext context) {
    const grey = Color(0xFF8696A0);
    const blue = Color(0xFF53BDEB);
    if (readAt != null) {
      return const Icon(Icons.done_all, size: 15, color: blue);
    }
    if (deliveredAt != null) {
      return const Icon(Icons.done_all, size: 15, color: grey);
    }
    return const Icon(Icons.done, size: 15, color: grey);
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
  final Future<void> Function(String kind) onAttachmentSelected;
  /// عند false تُخفى واجهة الإرفاق (قناة الفريق = نص فقط).
  final bool attachmentsEnabled;
  /// تلميح الحقل (مثل قناة الفريق)؛ عند null يُستخدم النص الافتراضي.
  final String? composerHint;
  final bool sending;

  const _ChatThread({
    required this.isAr,
    required this.sb,
    required this.conversationId,
    required this.currentUserId,
    required this.controller,
    required this.onSend,
    required this.onOpenedOrNewData,
    required this.onAttachmentSelected,
    this.attachmentsEnabled = true,
    this.composerHint,
    required this.sending,
  });

  @override
  State<_ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<_ChatThread> {
  final _scroll = ScrollController();

  Timer? _markReadDebounce;

  /// أول لقطة من البث — لا نُشغّل صوتاً؛ بعدها أي رسالة جديدة في الأعلى من الطرف الآخر.
  bool _incomingSoundPrimed = false;
  String? _lastTopMessageId;

  final Set<String> _hiddenMessageIds = {};
  StreamSubscription<List<Map<String, dynamic>>>? _hidesSub;

  bool _msgWithinHours(Map<String, dynamic> m, int hours) {
    final dt = _parseMsgTs(m['created_at']);
    if (dt == null) return false;
    return DateTime.now().difference(dt) < Duration(hours: hours);
  }

  Future<void> _loadHiddenForConversation() async {
    final uid = widget.currentUserId.trim();
    final cid = widget.conversationId.trim();
    if (uid.isEmpty || cid.isEmpty) return;
    try {
      final rows = await widget.sb
          .from('message_user_hides')
          .select('message_id')
          .eq('conversation_id', cid)
          .eq('user_id', uid);
      if (!mounted) return;
      setState(() {
        _hiddenMessageIds
          ..clear()
          ..addAll(
            rows
                .map((r) => (r['message_id'] ?? '').toString().trim())
                .where((s) => s.isNotEmpty),
          );
      });
    } catch (_) {}
  }

  Future<void> _hideMessageForMe(String messageId) async {
    final mid = messageId.trim();
    if (mid.isEmpty || !mounted) return;
    try {
      await widget.sb.rpc(
        'hide_chat_message_for_me',
        params: {'p_message_id': mid},
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isAr
                ? 'تعذّر إخفاء الرسالة'
                : 'Could not hide message'),
          ),
        );
      }
    }
  }

  Future<void> _onLongPressMessage({
    required BuildContext context,
    required Map<String, dynamic> m,
    required int visualIndex,
    required bool mine,
  }) async {
    final mid = (m['id'] ?? '').toString().trim();
    if (mid.isEmpty) return;
    final attachUrl = (m['attachment_url'] ?? '').toString().trim();
    final hasAttach = attachUrl.isNotEmpty;
    final deletedAt = _parseMsgTs(m['deleted_for_everyone_at']);
    final ocp = m['org_channel_post_id'];
    final isChannelMirror =
        ocp != null && ocp.toString().trim().isNotEmpty;
    final isLatest = visualIndex == 0;
    final canEdit =
        mine && deletedAt == null && isLatest && !isChannelMirror;
    final canRevoke =
        mine && deletedAt == null && _msgWithinHours(m, 48) && !isChannelMirror;

    if (!mine) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(widget.isAr ? 'حذف لي فقط' : 'Delete for me'),
                onTap: () => Navigator.pop(ctx, 'hide_me'),
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (choice == 'hide_me') await _hideMessageForMe(mid);
      return;
    }

    // رسائلي
    if (deletedAt != null) {
      final only = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(widget.isAr ? 'حذف لي فقط' : 'Delete for me'),
                onTap: () => Navigator.pop(ctx, 'hide_me'),
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (only == 'hide_me') await _hideMessageForMe(mid);
      return;
    }

    if (!canEdit && !canRevoke) {
      final only = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(widget.isAr ? 'حذف لي فقط' : 'Delete for me'),
                onTap: () => Navigator.pop(ctx, 'hide_me'),
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (only == 'hide_me') await _hideMessageForMe(mid);
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canEdit)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(widget.isAr
                      ? (hasAttach ? 'تعديل التعليق' : 'تعديل')
                      : (hasAttach ? 'Edit caption' : 'Edit')),
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
              if (canRevoke)
                ListTile(
                  leading: Icon(Icons.delete_forever_outlined,
                      color: Theme.of(ctx).colorScheme.error),
                  title: Text(
                    widget.isAr ? 'حذف للجميع' : 'Delete for everyone',
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, 'revoke'),
                ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(widget.isAr ? 'حذف لي فقط' : 'Delete for me'),
                onTap: () => Navigator.pop(ctx, 'hide_me'),
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (choice == 'hide_me') {
      await _hideMessageForMe(mid);
      return;
    }
    if (choice == 'edit') {
      final initial = (m['content'] ?? '').toString();
      final tc = TextEditingController(text: initial);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(widget.isAr ? 'تعديل الرسالة' : 'Edit message'),
          content: TextField(
            controller: tc,
            autofocus: true,
            minLines: 1,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: widget.isAr
                  ? (hasAttach ? 'التعليق على الوسيط' : 'النص الجديد')
                  : (hasAttach ? 'Caption' : 'New text'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(widget.isAr ? 'حفظ' : 'Save'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) {
        final next = tc.text.trim();
        tc.dispose();
        if (next.isEmpty && !hasAttach) return;
        try {
          await widget.sb.rpc(
            'edit_chat_message',
            params: {
              'p_message_id': mid,
              'p_new_content': next,
            },
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(widget.isAr
                    ? 'تعذّر التعديل (ربما وجود رد لاحق)'
                    : 'Could not edit (a newer reply may exist)'),
              ),
            );
          }
        }
      } else {
        tc.dispose();
      }
      return;
    }
    if (choice == 'revoke') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(widget.isAr ? 'حذف للجميع؟' : 'Delete for everyone?'),
          content: Text(
            widget.isAr
                ? 'تُحذف الرسالة من المحادثة لدى الطرفين (خلال 48 ساعة من إرسالها).'
                : 'Remove this message for both sides (within 48h of sending).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(widget.isAr ? 'حذف' : 'Delete'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      try {
        await widget.sb.rpc(
          'revoke_chat_message_for_everyone',
          params: {'p_message_id': mid},
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.isAr
                  ? 'تعذّر الحذف (انتهت المهلة أو لا صلاحية)'
                  : 'Could not delete (window or permission)'),
            ),
          );
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final uid = widget.currentUserId.trim();
    final cid = widget.conversationId.trim();
    if (uid.isNotEmpty && cid.isNotEmpty) {
      unawaited(_loadHiddenForConversation());
      _hidesSub = widget.sb
          .from('message_user_hides')
          .stream(primaryKey: const ['id'])
          .eq('user_id', uid)
          .listen((rows) {
        if (!mounted) return;
        final forConv = rows
            .where((r) =>
                (r['conversation_id'] ?? '').toString().trim() == cid)
            .toList();
        setState(() {
          _hiddenMessageIds
            ..clear()
            ..addAll(
              forConv
                  .map((r) => (r['message_id'] ?? '').toString().trim())
                  .where((s) => s.isNotEmpty),
            );
        });
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_markIncomingDelivered());
      unawaited(widget.onOpenedOrNewData());
    });
  }

  Future<void> _markIncomingDelivered() async {
    try {
      await widget.sb.rpc(
        'mark_chat_messages_delivered',
        params: {'p_cid': widget.conversationId},
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _hidesSub?.cancel();
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

  void _onIncomingRowsSnapshot(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return;
    final top = rows.first;
    final id = top['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final sender = top['sender_id']?.toString() ?? '';
    if (!_incomingSoundPrimed) {
      _incomingSoundPrimed = true;
      _lastTopMessageId = id;
      return;
    }
    if (id == _lastTopMessageId) return;
    _lastTopMessageId = id;
    if (sender != widget.currentUserId) {
      playChatIncomingMessageSound();
    }
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
          child: ColoredBox(
            color: _kWaChatBg,
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: msgStream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: AppLogoLoading());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(widget.isAr
                        ? 'تعذر تحميل الرسائل'
                        : 'Failed to load messages'),
                  );
                }

                final rows = snap.data ?? const <Map<String, dynamic>>[];
                final visible = rows
                    .where((r) =>
                        !_hiddenMessageIds.contains((r['id'] ?? '').toString()))
                    .toList();

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _onIncomingRowsSnapshot(visible);
                });

                if (visible.isEmpty) {
                  return Center(
                    child: Text(
                      widget.isAr
                          ? 'ابدأ المحادثة الآن'
                          : 'Start the conversation',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: _kWaTimeColor,
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
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final cs = Theme.of(context).colorScheme;
                    final m = visible[i];
                    final sender = (m['sender_id'] ?? '').toString();
                    final text = (m['content'] ?? '').toString();
                    final attachUrl =
                        (m['attachment_url'] ?? '').toString().trim();
                    final attachType = (m['attachment_type'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase();
                    final mine = sender == widget.currentUserId;
                    final timeStr = _fmtMsgTimeFromRow(m, isAr: widget.isAr);
                    final readAt = _parseMsgTs(m['read_at']);
                    final deliveredAt = _parseMsgTs(m['delivered_at']);
                    final deletedAt = _parseMsgTs(m['deleted_for_everyone_at']);
                    final editedAt = _parseMsgTs(m['edited_at']);

                    final bubbleColor =
                        mine ? _kWaBubbleSent : _kWaBubbleReceived;
                    final br = BorderRadius.only(
                      topLeft: const Radius.circular(10),
                      topRight: const Radius.circular(10),
                      bottomLeft: Radius.circular(mine ? 10 : 2),
                      bottomRight: Radius.circular(mine ? 2 : 10),
                    );

                    final bubble = Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78,
                      ),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: br,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: mine
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (deletedAt != null)
                            Text(
                              widget.isAr
                                  ? 'حُذفت هذه الرسالة'
                                  : 'This message was deleted',
                              style: TextStyle(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w600,
                                color: _kWaTimeColor,
                              ),
                            )
                          else ...[
                            if (attachUrl.isNotEmpty && attachType == 'image')
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 220,
                                    ),
                                    child: CachedNetworkImage(
                                      imageUrl: attachUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => const SizedBox(
                                        height: 120,
                                        child: Center(
                                          child: AppLogoLoading(
                                            compact: true,
                                            size: 28,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (_, __, ___) => Icon(
                                        Icons.broken_image_outlined,
                                        color: cs.error,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (attachUrl.isNotEmpty &&
                                attachType == 'location')
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  onTap: () async {
                                    final u = Uri.tryParse(attachUrl);
                                    if (u != null && await canLaunchUrl(u)) {
                                      await launchUrl(
                                        u,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    }
                                  },
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.location_on_rounded,
                                        color: cs.primary,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          widget.isAr
                                              ? 'فتح الموقع على الخريطة'
                                              : 'Open location in Maps',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: cs.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (text.trim().isNotEmpty &&
                                text.trim() != attachUrl)
                              Linkify(
                                text: text,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      height: 1.35,
                                      color: const Color(0xFF111B21),
                                    ),
                                linkStyle: const TextStyle(
                                  color: Color(0xFF039BE5),
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                ),
                                onOpen: (link) async {
                                  final u = Uri.tryParse(link.url);
                                  if (u != null && await canLaunchUrl(u)) {
                                    await launchUrl(
                                      u,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                },
                              ),
                            if (editedAt != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Align(
                                  alignment: mine
                                      ? AlignmentDirectional.centerEnd
                                      : AlignmentDirectional.centerStart,
                                  child: Text(
                                    widget.isAr ? 'تم التعديل' : 'Edited',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      fontStyle: FontStyle.italic,
                                      color: _kWaTimeColor,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (timeStr.isNotEmpty)
                                Text(
                                  timeStr,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: _kWaTimeColor,
                                  ),
                                ),
                              if (mine) ...[
                                if (timeStr.isNotEmpty)
                                  const SizedBox(width: 4),
                                _WaReceiptTicks(
                                  readAt: readAt,
                                  deliveredAt: deliveredAt,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    );

                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () => _onLongPressMessage(
                          context: context,
                          m: m,
                          visualIndex: i,
                          mine: mine,
                        ),
                        child: bubble,
                      ),
                    );
                  },
                );
              },
            ),
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
                if (widget.attachmentsEnabled)
                  PopupMenuButton<String>(
                    tooltip: widget.isAr ? 'إرفاق' : 'Attach',
                    icon: Icon(
                      Icons.add_circle_outline_rounded,
                      color: cs.primary,
                      size: 28,
                    ),
                    onSelected: (v) {
                      unawaited(widget.onAttachmentSelected(v));
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'media',
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.perm_media_outlined),
                          title: Text(widget.isAr ? 'وسائط' : 'Media'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'loc',
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on_outlined),
                          title: Text(widget.isAr ? 'موقع' : 'Location'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'contact',
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.contact_phone_outlined),
                          title: Text(widget.isAr ? 'جهة اتصال' : 'Contact'),
                        ),
                      ),
                    ],
                  )
                else
                  Tooltip(
                    message: widget.isAr
                        ? 'قناة الفريق — نص فقط'
                        : 'Team channel — text only',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.campaign_outlined,
                        color: cs.outline,
                        size: 26,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: widget.composerHint ??
                          (widget.isAr ? 'اكتب رسالة…' : 'Type a message…'),
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
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: AppLogoLoading(compact: true, size: 20),
                        )
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
